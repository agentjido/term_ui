defmodule TermUI.Widget.FormBuilder do
  @moduledoc """
  A pure form with field, group, and submit validation.

  The parent owns the form value and all validation functions. A field
  validator receives one field value. A group validator receives the values
  for its configured fields. A submit validator receives all form values.

      fields = [
        %{id: :password, label: "Password", required: true},
        %{id: :confirmation, label: "Confirm", required: true}
      ]

      groups = [
        %{
          id: :passwords,
          fields: [:password, :confirmation],
          validators: [fn values ->
            if values.password == values.confirmation,
              do: :ok,
              else: {:error, :confirmation, "does not match"}
          end]
        }
      ]

      form = FormBuilder.init(fields: fields, groups: groups)

  Field validators return `:ok` or `{:error, message}`. Group and submit
  validators return `:ok`, `{:error, field_id, message}`, or
  `{:error, %{field_id => message}}`. Enter validates all sources. If a rule
  fails, `active` points to the first invalid field. No callback runs outside
  this pure update.
  """

  @behaviour TermUI.Widget

  alias TermUI.{Event, Style}
  alias TermUI.Widget.Helpers

  # This helper terminates invalid application validator contracts by design.
  @dialyzer {:nowarn_function, invalid_validator_result!: 2}

  @type field_validator :: (term() -> :ok | {:error, String.t()})
  @type values_validator ::
          (map() ->
             :ok
             | {:error, term(), String.t()}
             | {:error, %{optional(term()) => String.t()}})
  @type field :: %{
          required(:id) => term(),
          required(:label) => String.t(),
          required(:type) => :text | :checkbox | :select,
          optional(:options) => [term()],
          optional(:required) => boolean(),
          optional(:validators) => [field_validator()]
        }
  @type group :: %{
          required(:id) => term(),
          required(:fields) => [term()],
          optional(:validators) => [values_validator()]
        }
  @type error_source :: {:field, term()} | {:group, term()} | :submit
  @type t :: %__MODULE__{
          fields: [field()],
          groups: [group()],
          validators: [values_validator()],
          values: map(),
          active: non_neg_integer(),
          errors: %{optional(term()) => String.t()},
          error_sources: %{optional(error_source()) => map()},
          submit_label: String.t()
        }

  defstruct fields: [],
            groups: [],
            validators: [],
            values: %{},
            active: 0,
            errors: %{},
            error_sources: %{},
            submit_label: "Submit"

  @impl true
  def init(opts) do
    fields = opts |> Keyword.get(:fields, []) |> Enum.map(&normalize_field/1)
    groups = opts |> Keyword.get(:groups, []) |> Enum.map(&normalize_group/1)
    validators = opts |> Keyword.get(:validators, []) |> normalize_validators!(:submit)
    validate_unique_ids!(fields, groups)
    validate_group_fields!(fields, groups)

    defaults =
      Map.new(fields, fn field -> {field.id, Map.get(field, :default, default_value(field))} end)

    %__MODULE__{
      fields: fields,
      groups: groups,
      validators: validators,
      values: Map.merge(defaults, Keyword.get(opts, :values, %{})),
      submit_label: Keyword.get(opts, :submit_label, "Submit")
    }
  end

  @impl true
  def update(%Event.Key{key: :tab}, state), do: move(state, 1)
  def update(%Event.Key{key: :up}, state), do: move(state, -1)
  def update(%Event.Key{key: :down}, state), do: move(state, 1)
  def update(%Event.Key{key: :space}, state), do: toggle_or_cycle(state)
  def update(%Event.Text{text: " "}, state), do: toggle_or_insert_space(state)
  def update(%Event.Key{key: :left}, state), do: cycle(state, -1)
  def update(%Event.Key{key: :right}, state), do: cycle(state, 1)
  def update(%Event.Key{key: :backspace}, state), do: edit_text(state, &drop_last/1)
  def update(%Event.Text{text: text}, state), do: edit_text(state, &(&1 <> clean(text)))
  def update(%Event.Paste{content: text}, state), do: edit_text(state, &(&1 <> clean(text)))

  def update(%Event.Key{key: :enter}, state) do
    case validate(state) do
      %{errors: errors} = checked when map_size(errors) == 0 ->
        {checked, [{:submit, checked.values}]}

      checked ->
        {checked, [{:invalid, checked.errors}]}
    end
  end

  def update(_event, state), do: {state, []}

  @impl true
  def mouse(%Event.Mouse{action: action, button: :left, y: y}, state, {_width, height})
      when action in [:press, :release] do
    case field_at(state, y, height) do
      nil ->
        {state, []}

      index ->
        state = %{state | active: index}
        if action == :release, do: activate_field(state), else: {state, []}
    end
  end

  def mouse(event, state, _dimensions), do: update(event, state)

  @impl true
  def view(state, {_width, height} = dimensions) do
    label_style = Style.new(fg: :cyan)
    active_style = Style.new(attrs: [:reverse])
    error_style = Style.new(fg: :red)

    rows =
      state.fields
      |> Enum.with_index()
      |> Enum.flat_map(fn {field, index} ->
        value = Map.get(state.values, field.id)
        value_text = render_value(field, value)
        style = if index == state.active, do: active_style, else: Style.new()
        row = [{field.label <> ": ", label_style}, {value_text, style}]

        case Map.get(state.errors, field.id) do
          nil -> [row]
          error -> [row, [{"  " <> error, error_style}]]
        end
      end)

    Helpers.frame(Enum.take(rows, height), dimensions)
  end

  @doc "Validates all fields, groups, and submit rules, then focuses the first error."
  @spec validate(t()) :: t()
  def validate(state) do
    state = Enum.reduce(state.fields, state, &validate_field(&2, &1.id))
    state = Enum.reduce(state.groups, state, &validate_group(&2, &1.id))
    state = validate_submit_rules(state)
    focus_first_error(state)
  end

  @doc "Validates one field and replaces only errors from that field rule."
  @spec validate_field(t(), term()) :: t()
  def validate_field(state, id) do
    case Enum.find(state.fields, &(&1.id == id)) do
      nil -> state
      field -> put_source_errors(state, {:field, id}, field_errors(field, state.values))
    end
  end

  @doc "Validates one group and replaces only errors from that group."
  @spec validate_group(t(), term()) :: t()
  def validate_group(state, id) do
    case Enum.find(state.groups, &(&1.id == id)) do
      nil ->
        state

      group ->
        values = Map.take(state.values, group.fields)
        errors = values_errors(group.validators, values, List.first(group.fields), state)
        put_source_errors(state, {:group, id}, errors)
    end
  end

  @doc "Returns the ID of the active field, or nil when the form has no fields."
  @spec focused_field(t()) :: term() | nil
  def focused_field(state) do
    case Enum.at(state.fields, state.active) do
      nil -> nil
      field -> field.id
    end
  end

  @doc "Sets one field value and revalidates displayed errors affected by that field."
  @spec put_value(t(), term(), term()) :: t()
  def put_value(state, id, value) do
    state
    |> Map.update!(:values, &Map.put(&1, id, value))
    |> revalidate_changed(id)
  end

  defp move(%{fields: []} = state, _delta), do: {state, []}

  defp move(state, delta) do
    active = rem(state.active + delta + length(state.fields), length(state.fields))
    {%{state | active: active}, []}
  end

  defp toggle_or_cycle(state) do
    case Enum.at(state.fields, state.active) do
      %{type: :checkbox, id: id} -> changed(state, id, not Map.get(state.values, id, false))
      %{type: :select} -> cycle(state, 1)
      _field -> {state, []}
    end
  end

  defp toggle_or_insert_space(state) do
    case Enum.at(state.fields, state.active) do
      %{type: type} when type in [:checkbox, :select] -> toggle_or_cycle(state)
      _field -> edit_text(state, &(&1 <> " "))
    end
  end

  defp activate_field(state) do
    case Enum.at(state.fields, state.active) do
      %{type: type} when type in [:checkbox, :select] -> toggle_or_cycle(state)
      _field -> {state, []}
    end
  end

  defp field_at(state, y, height) when y >= 0 and y < height do
    state.fields
    |> Enum.with_index()
    |> Enum.reduce_while(0, fn {field, index}, row ->
      next_row = row + if(Map.has_key?(state.errors, field.id), do: 2, else: 1)

      if y == row,
        do: {:halt, {:found, index}},
        else: {:cont, next_row}
    end)
    |> case do
      {:found, index} -> index
      _row -> nil
    end
  end

  defp field_at(_state, _y, _height), do: nil

  defp cycle(state, delta) do
    case Enum.at(state.fields, state.active) do
      %{type: :select, id: id, options: options} when options != [] ->
        current = Enum.find_index(options, &(&1 == Map.get(state.values, id))) || 0
        index = rem(current + delta + length(options), length(options))
        changed(state, id, Enum.at(options, index))

      _field ->
        {state, []}
    end
  end

  defp edit_text(state, fun) do
    case Enum.at(state.fields, state.active) do
      %{type: :text, id: id} -> changed(state, id, fun.(to_string(Map.get(state.values, id, ""))))
      _field -> {state, []}
    end
  end

  defp changed(state, id, value),
    do: {put_value(state, id, value), [{:changed, id, value}]}

  defp revalidate_changed(state, id) do
    state =
      if Map.has_key?(state.error_sources, {:field, id}),
        do: validate_field(state, id),
        else: state

    state =
      Enum.reduce(state.groups, state, fn group, state ->
        if id in group.fields and Map.has_key?(state.error_sources, {:group, group.id}),
          do: validate_group(state, group.id),
          else: state
      end)

    if Map.has_key?(state.error_sources, :submit),
      do: validate_submit_rules(state),
      else: state
  end

  defp validate_submit_rules(state) do
    errors = values_errors(state.validators, state.values, nil, state)
    put_source_errors(state, :submit, errors)
  end

  defp field_errors(field, values) do
    value = Map.get(values, field.id)

    if Map.get(field, :required, false) and blank?(value),
      do: %{field.id => "is required"},
      else: field_validator_errors(field, value)
  end

  defp field_validator_errors(field, value),
    do:
      Enum.reduce_while(field.validators, %{}, fn validator, _errors ->
        field_validator_result(validator.(value), field.id)
      end)

  defp field_validator_result(:ok, _id), do: {:cont, %{}}

  defp field_validator_result({:error, message}, id) when is_binary(message),
    do: {:halt, %{id => message}}

  defp field_validator_result(result, _id), do: invalid_validator_result!(result, :field)

  defp values_errors(validators, values, default_field, state) do
    Enum.reduce(validators, %{}, fn validator, errors ->
      validator.(values)
      |> normalize_values_result(default_field)
      |> validate_error_fields!(state)
      |> Map.merge(errors, fn _id, new, _old -> new end)
    end)
  end

  defp normalize_values_result(:ok, _default_field), do: %{}

  defp normalize_values_result({:error, id, message}, _default_field) when is_binary(message),
    do: %{id => message}

  defp normalize_values_result({:error, errors}, _default_field) when is_map(errors),
    do: normalize_error_map!(errors)

  defp normalize_values_result({:error, message}, default_field)
       when is_binary(message) and not is_nil(default_field),
       do: %{default_field => message}

  defp normalize_values_result(result, _default_field),
    do: invalid_validator_result!(result, :values)

  defp normalize_error_map!(errors) do
    Enum.reduce(errors, %{}, fn
      {id, message}, acc when is_binary(message) -> Map.put(acc, id, message)
      {_id, message}, _acc -> invalid_validator_result!(message, :message)
    end)
  end

  defp validate_error_fields!(errors, state) do
    field_ids = MapSet.new(state.fields, & &1.id)

    Enum.each(Map.keys(errors), fn id ->
      if not MapSet.member?(field_ids, id) do
        raise ArgumentError, "validator returned an unknown field ID: #{inspect(id)}"
      end
    end)

    errors
  end

  defp invalid_validator_result!(result, kind) do
    raise ArgumentError, "invalid #{kind} validator result: #{inspect(result)}"
  end

  defp put_source_errors(state, source, errors) do
    error_sources =
      if map_size(errors) == 0,
        do: Map.delete(state.error_sources, source),
        else: Map.put(state.error_sources, source, errors)

    %{state | error_sources: error_sources, errors: merge_errors(state, error_sources)}
  end

  defp merge_errors(state, error_sources) do
    source_order =
      Enum.map(state.fields, &{:field, &1.id}) ++
        Enum.map(state.groups, &{:group, &1.id}) ++ [:submit]

    Enum.reduce(source_order, %{}, fn source, errors ->
      source_errors = Map.get(error_sources, source, %{})
      Map.merge(errors, source_errors, fn _id, first, _later -> first end)
    end)
  end

  defp focus_first_error(state) do
    case Enum.find_index(state.fields, &Map.has_key?(state.errors, &1.id)) do
      nil -> state
      active -> %{state | active: active}
    end
  end

  defp render_value(%{type: :checkbox}, true), do: "[x]"
  defp render_value(%{type: :checkbox}, _value), do: "[ ]"
  defp render_value(%{type: :select}, value), do: "‹ " <> to_string(value || "") <> " ›"
  defp render_value(_field, value), do: to_string(value || "")

  defp default_value(%{type: :checkbox}), do: false
  defp default_value(%{type: :select, options: [first | _]}), do: first
  defp default_value(_field), do: ""

  defp normalize_field(%{id: id, label: label} = field) do
    validators = field |> Map.get(:validators, []) |> normalize_validators!({:field, id})

    field
    |> Map.put(:id, id)
    |> Map.put(:label, to_string(label))
    |> Map.put(:validators, validators)
    |> Map.put_new(:type, :text)
    |> Map.put_new(:options, [])
  end

  defp normalize_field({id, label}),
    do: %{id: id, label: to_string(label), type: :text, options: [], validators: []}

  defp normalize_group(%{id: id, fields: fields} = group) when is_list(fields) do
    validators = group |> Map.get(:validators, []) |> normalize_validators!({:group, id})
    group |> Map.put(:id, id) |> Map.put(:fields, fields) |> Map.put(:validators, validators)
  end

  defp normalize_group(group) do
    raise ArgumentError, "validation group needs an ID and field list: #{inspect(group)}"
  end

  defp normalize_validators!(validators, source) when is_list(validators) do
    Enum.map(validators, fn validator ->
      if is_function(validator, 1),
        do: validator,
        else: raise(ArgumentError, "#{inspect(source)} validator must have arity 1")
    end)
  end

  defp normalize_validators!(_validators, source) do
    raise ArgumentError, "#{inspect(source)} validators must be a list"
  end

  defp validate_unique_ids!(fields, groups) do
    ensure_unique_ids!(Enum.map(fields, & &1.id), "field")
    ensure_unique_ids!(Enum.map(groups, & &1.id), "validation group")
  end

  defp ensure_unique_ids!(ids, label) do
    if MapSet.size(MapSet.new(ids)) != length(ids),
      do: raise(ArgumentError, "#{label} IDs must be unique")
  end

  defp validate_group_fields!(fields, groups) do
    field_ids = MapSet.new(fields, & &1.id)
    Enum.each(groups, &validate_group_field_ids!(&1, field_ids))
  end

  defp validate_group_field_ids!(group, field_ids),
    do: Enum.each(group.fields, &validate_group_field_id!(&1, field_ids))

  defp validate_group_field_id!(id, field_ids) do
    if not MapSet.member?(field_ids, id),
      do: raise(ArgumentError, "validation group contains an unknown field ID: #{inspect(id)}")
  end

  defp blank?(value), do: value in [nil, "", false, []]
  defp clean(text), do: String.replace(text, ~r/[\x00-\x1F\x7F]/u, "")
  defp drop_last(text), do: text |> String.graphemes() |> Enum.drop(-1) |> Enum.join()
end
