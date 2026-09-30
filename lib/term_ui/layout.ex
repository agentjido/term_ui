defmodule TermUI.Layout do
  @moduledoc """
  Pure rectangle allocation and frame placement.

  Layout rectangles use zero-based coordinates because mouse events use the
  same coordinate system. `place/3` converts them to the one-based coordinates
  used by `TermUI.Frame.overlay/4`.

  A track can be fixed, fill, weighted, percentage-based, or bounded. Use
  `content/2` when the application has measured a child's content size.
  """

  alias TermUI.{Frame, Mouse}
  alias TermUI.Mouse.Region

  @type rect ::
          {x :: non_neg_integer(), y :: non_neg_integer(), width :: non_neg_integer(),
           height :: non_neg_integer()}
  @type maximum :: non_neg_integer() | :infinity
  @type base_track ::
          non_neg_integer()
          | :fill
          | {:weight, pos_integer() | float()}
          | {:percentage, number()}
  @type track :: base_track() | {:bounded, base_track(), non_neg_integer(), maximum()}
  @type padding ::
          non_neg_integer()
          | {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}

  defguardp is_rect(x, y, width, height)
            when is_integer(x) and x >= 0 and is_integer(y) and y >= 0 and is_integer(width) and
                   width >= 0 and is_integer(height) and height >= 0

  @doc "Creates a root rectangle from frame dimensions."
  @spec new({non_neg_integer(), non_neg_integer()}) ::
          {0, 0, non_neg_integer(), non_neg_integer()}
  def new({width, height})
      when is_integer(width) and width >= 0 and is_integer(height) and height >= 0,
      do: {0, 0, width, height}

  @doc "Returns a rectangle's frame dimensions."
  @spec dimensions(rect()) :: {non_neg_integer(), non_neg_integer()}
  def dimensions({_x, _y, width, height}), do: {width, height}

  @doc "Creates a fixed-size track. A non-negative integer is the direct form."
  @spec fixed(non_neg_integer()) :: non_neg_integer()
  def fixed(size), do: non_negative_integer!(size, :size)

  @doc "Creates a fill track. The direct form is `:fill`."
  @spec fill() :: :fill
  def fill, do: :fill

  @doc "Creates a percentage track from 0 through 100 percent."
  @spec percentage(number()) :: {:percentage, number()}
  def percentage(value) when is_number(value) and value >= 0 and value <= 100,
    do: {:percentage, value}

  def percentage(value),
    do:
      raise(
        ArgumentError,
        "percentage must be a number from 0 through 100, got: #{inspect(value)}"
      )

  @doc "Creates a weighted track. This is the v2 replacement for a ratio constraint."
  @spec ratio(pos_integer() | float()) :: {:weight, pos_integer() | float()}
  def ratio(value) when is_number(value) and value > 0, do: {:weight, value}

  def ratio(value),
    do: raise(ArgumentError, "ratio must be a positive number, got: #{inspect(value)}")

  @doc "Adds optional `:min` and `:max` cell bounds to a track."
  @spec bounded(base_track(), keyword()) ::
          {:bounded, base_track(), non_neg_integer(), maximum()}
  def bounded(track, opts \\ []) when is_list(opts) do
    validate_bound_options!(opts)
    minimum = opts |> Keyword.get(:min, 0) |> non_negative_integer!(:min)
    maximum = opts |> Keyword.get(:max, :infinity) |> maximum!(:max)

    if maximum != :infinity and minimum > maximum do
      raise ArgumentError, "minimum size cannot be greater than maximum size"
    end

    :ok = validate_track!(track)
    {:bounded, track, minimum, maximum}
  end

  @doc "Creates a fixed track from measured content with optional cell bounds."
  @spec content(non_neg_integer(), keyword()) ::
          {:bounded, non_neg_integer(), non_neg_integer(), maximum()}
  def content(measured_size, opts \\ []) do
    measured_size
    |> fixed()
    |> bounded(opts)
  end

  @doc "Insets a rectangle by uniform or per-side padding."
  @spec inset(rect(), padding()) :: rect()
  def inset(rect, padding) when is_integer(padding) and padding >= 0,
    do: inset(rect, {padding, padding, padding, padding})

  def inset({x, y, width, height}, {top, right, bottom, left})
      when is_rect(x, y, width, height) and is_integer(top) and top >= 0 and is_integer(right) and
             right >= 0 and is_integer(bottom) and bottom >= 0 and is_integer(left) and left >= 0 do
    inset_x = min(left, width)
    inset_y = min(top, height)

    {
      x + inset_x,
      y + inset_y,
      max(width - left - right, 0),
      max(height - top - bottom, 0)
    }
  end

  @doc "Returns a child rectangle clipped to its parent."
  @spec at(rect(), {non_neg_integer(), non_neg_integer()}, {non_neg_integer(), non_neg_integer()}) ::
          rect()
  def at({x, y, width, height}, {child_x, child_y}, {child_width, child_height})
      when is_rect(x, y, width, height) and is_integer(child_x) and child_x >= 0 and
             is_integer(child_y) and child_y >= 0 and is_integer(child_width) and child_width >= 0 and
             is_integer(child_height) and child_height >= 0 do
    offset_x = min(child_x, width)
    offset_y = min(child_y, height)

    {
      x + offset_x,
      y + offset_y,
      min(child_width, max(width - offset_x, 0)),
      min(child_height, max(height - offset_y, 0))
    }
  end

  @doc "Allocates horizontal tracks inside a rectangle."
  @spec row(rect(), [track()], keyword()) :: [rect()]
  def row({x, y, width, height}, tracks, opts \\ [])
      when is_rect(x, y, width, height) and is_list(tracks) do
    gap = opts |> Keyword.get(:gap, 0) |> non_negative_integer!(:gap)
    sizes = allocate(tracks, width, gap)
    boundary = x + width

    sizes
    |> Enum.map_reduce(x, fn size, cursor ->
      start = min(cursor, boundary)
      size = min(size, boundary - start)
      {{start, y, size, height}, min(start + size + gap, boundary)}
    end)
    |> elem(0)
  end

  @doc "Allocates vertical tracks inside a rectangle."
  @spec column(rect(), [track()], keyword()) :: [rect()]
  def column({x, y, width, height}, tracks, opts \\ [])
      when is_rect(x, y, width, height) and is_list(tracks) do
    gap = opts |> Keyword.get(:gap, 0) |> non_negative_integer!(:gap)
    sizes = allocate(tracks, height, gap)
    boundary = y + height

    sizes
    |> Enum.map_reduce(y, fn size, cursor ->
      start = min(cursor, boundary)
      size = min(size, boundary - start)
      {{x, start, width, size}, min(start + size + gap, boundary)}
    end)
    |> elem(0)
  end

  @doc "Allocates a row-major grid with equal or explicit row and column tracks."
  @spec grid(rect(), non_neg_integer(), keyword()) :: [rect()]
  def grid(rect, item_count, opts \\ [])

  def grid({x, y, width, height}, 0, _opts) when is_rect(x, y, width, height), do: []

  def grid({x, y, width, height}, item_count, opts)
      when is_rect(x, y, width, height) and is_integer(item_count) and item_count > 0 do
    column_gap =
      opts
      |> Keyword.get(:column_gap, Keyword.get(opts, :gap, 0))
      |> non_negative_integer!(:column_gap)

    row_gap =
      opts
      |> Keyword.get(:row_gap, Keyword.get(opts, :gap, 0))
      |> non_negative_integer!(:row_gap)

    if Keyword.has_key?(opts, :column_tracks) or Keyword.has_key?(opts, :row_tracks) do
      constrained_grid(
        {x, y, width, height},
        item_count,
        opts,
        column_gap,
        row_gap
      )
    else
      equal_grid({x, y, width, height}, item_count, opts, column_gap, row_gap)
    end
  end

  @doc "Places and clips a child frame inside a rectangle."
  @spec place(Frame.t(), Frame.t(), rect()) :: Frame.t()
  def place(%Frame{} = base, %Frame{}, {x, y, 0, height}) when is_rect(x, y, 0, height),
    do: base

  def place(%Frame{} = base, %Frame{}, {x, y, width, 0}) when is_rect(x, y, width, 0),
    do: base

  def place(%Frame{} = base, %Frame{} = child, {x, y, width, height})
      when is_rect(x, y, width, height) do
    width = min(width, max(base.width - x, 0))
    height = min(height, max(base.height - y, 0))

    if width == 0 or height == 0 do
      base
    else
      clipped = Frame.overlay(Frame.new(width, height), child, 1, 1)
      Frame.overlay(base, clipped, x + 1, y + 1)
    end
  end

  @doc "Creates a mouse region from a non-empty rectangle."
  @spec region(term(), rect(), keyword()) :: Region.t() | nil
  def region(id, rect, opts \\ [])

  def region(_id, {x, y, 0, height}, _opts) when is_rect(x, y, 0, height), do: nil
  def region(_id, {x, y, width, 0}, _opts) when is_rect(x, y, width, 0), do: nil

  def region(id, {x, y, width, height}, opts) when is_rect(x, y, width, height),
    do: Mouse.region(id, x, y, width, height, opts)

  defp allocate([], _length, _gap), do: []

  defp allocate(tracks, length, gap) do
    if Enum.any?(tracks, &constrained_track?/1),
      do: allocate_constrained(tracks, length, gap),
      else: allocate_existing(tracks, length, gap)
  end

  defp allocate_existing(tracks, length, gap) do
    gap_total = gap * max(length(tracks) - 1, 0)
    available = max(length - gap_total, 0)
    fixed_total = Enum.reduce(tracks, 0, fn track, total -> total + fixed_size(track) end)
    flexible_space = max(available - fixed_total, 0)
    flexible_sizes = weighted_sizes(tracks, flexible_space)

    {sizes, _remaining, _flexible_sizes} =
      Enum.reduce(tracks, {[], available, flexible_sizes}, fn track,
                                                              {sizes, remaining, flexible_sizes} ->
        if flexible?(track) do
          [flexible_size | rest] = flexible_sizes
          size = min(flexible_size, remaining)
          {[size | sizes], remaining - size, rest}
        else
          size = min(fixed_size(track), remaining)
          {[size | sizes], remaining - size, flexible_sizes}
        end
      end)

    Enum.reverse(sizes)
  end

  defp allocate_constrained(tracks, length, gap) do
    available = max(length - gap * max(length(tracks) - 1, 0), 0)
    specs = Enum.map(tracks, &normalize_track!/1)
    minimums = Enum.map(specs, & &1.min)

    if Enum.sum(minimums) > available do
      largest_remainder(minimums, available, Enum.sum(minimums))
    else
      {sizes, remaining} = allocate_requested_sizes(specs, minimums, available)
      {sizes, _remaining} = allocate_bounded_flexible(specs, sizes, remaining)
      sizes
    end
  end

  defp allocate_requested_sizes(specs, sizes, available) do
    remaining = available - Enum.sum(sizes)

    specs
    |> Enum.with_index()
    |> Enum.reject(fn {spec, _index} -> spec.kind == :flexible end)
    |> Enum.sort_by(fn {spec, index} -> {request_priority(spec), index} end)
    |> Enum.reduce({sizes, remaining}, fn {spec, index}, {sizes, remaining} ->
      requested = spec |> requested_size(available) |> clamp(spec.min, spec.max)
      addition = min(max(requested - Enum.at(sizes, index), 0), remaining)
      {List.update_at(sizes, index, &(&1 + addition)), remaining - addition}
    end)
  end

  defp allocate_bounded_flexible(_specs, sizes, 0), do: {sizes, 0}

  defp allocate_bounded_flexible(specs, sizes, remaining) do
    active =
      specs
      |> Enum.with_index()
      |> Enum.filter(fn {spec, index} ->
        spec.kind == :flexible and below_maximum?(Enum.at(sizes, index), spec.max)
      end)

    if active == [] do
      {sizes, remaining}
    else
      weights = Enum.map(active, fn {spec, _index} -> spec.weight end)
      additions = largest_remainder(weights, remaining, Enum.sum(weights))

      {sizes, consumed} =
        active
        |> Enum.zip(additions)
        |> Enum.reduce({sizes, 0}, fn {{spec, index}, addition}, {sizes, consumed} ->
          current = Enum.at(sizes, index)
          addition = cap_addition(addition, current, spec.max)
          {List.update_at(sizes, index, &(&1 + addition)), consumed + addition}
        end)

      if consumed == 0,
        do: {sizes, remaining},
        else: allocate_bounded_flexible(specs, sizes, remaining - consumed)
    end
  end

  defp weighted_sizes(tracks, available) do
    weights = tracks |> Enum.filter(&flexible?/1) |> Enum.map(&weight/1)

    case Enum.sum(weights) do
      total when total > 0 -> largest_remainder(weights, available, total)
      _total -> []
    end
  end

  defp largest_remainder(weights, available, total) do
    shares = Enum.map(weights, &(available * &1 / total))
    base = Enum.map(shares, &floor/1)
    remainder = available - Enum.sum(base)

    winners =
      shares
      |> Enum.with_index()
      |> Enum.sort_by(fn {share, index} -> {-(share - floor(share)), index} end)
      |> Enum.take(remainder)
      |> MapSet.new(fn {_share, index} -> index end)

    base
    |> Enum.with_index()
    |> Enum.map(fn {size, index} -> size + if(MapSet.member?(winners, index), do: 1, else: 0) end)
  end

  defp fixed_size(track) when is_integer(track) and track >= 0, do: track
  defp fixed_size(_track), do: 0
  defp flexible?(:fill), do: true
  defp flexible?({:weight, weight}) when is_number(weight) and weight > 0, do: true
  defp flexible?(_track), do: false
  defp weight(:fill), do: 1.0
  defp weight({:weight, weight}), do: weight * 1.0
  defp ceil_div(value, divisor), do: div(value + divisor - 1, divisor)

  defp constrained_grid(rect, item_count, opts, column_gap, row_gap) do
    column_tracks =
      grid_tracks(opts, :column_tracks, :columns, 2)

    row_tracks =
      grid_tracks(opts, :row_tracks, :rows, ceil_div(item_count, length(column_tracks)))

    columns = length(column_tracks)
    rows = length(row_tracks)
    cell_count = min(item_count, columns * rows)
    column_rects = row(rect, column_tracks, gap: column_gap)
    row_rects = column(rect, row_tracks, gap: row_gap)

    Enum.map(0..(cell_count - 1), fn index ->
      {cell_x, _y, cell_width, _height} = Enum.at(column_rects, rem(index, columns))
      {_x, cell_y, _width, cell_height} = Enum.at(row_rects, div(index, columns))
      {cell_x, cell_y, cell_width, cell_height}
    end)
  end

  defp equal_grid({x, y, width, height}, item_count, opts, column_gap, row_gap) do
    columns = opts |> Keyword.get(:columns, 2) |> positive_integer!(:columns)
    rows = opts |> Keyword.get(:rows, ceil_div(item_count, columns)) |> positive_integer!(:rows)
    cell_count = min(item_count, columns * rows)

    Enum.map(0..(cell_count - 1), fn index ->
      column_index = rem(index, columns)
      row_index = div(index, columns)
      {cell_x, cell_width} = equal_track(x, width, columns, column_gap, column_index)
      {cell_y, cell_height} = equal_track(y, height, rows, row_gap, row_index)
      {cell_x, cell_y, cell_width, cell_height}
    end)
  end

  defp grid_tracks(opts, tracks_key, count_key, default_count) do
    case Keyword.fetch(opts, tracks_key) do
      {:ok, [_track | _rest] = tracks} ->
        Enum.each(tracks, &validate_track!/1)
        tracks

      {:ok, invalid} ->
        raise ArgumentError,
              "#{tracks_key} must be a non-empty track list, got: #{inspect(invalid)}"

      :error ->
        count = opts |> Keyword.get(count_key, default_count) |> positive_integer!(count_key)
        List.duplicate(:fill, count)
    end
  end

  defp constrained_track?({:percentage, _value}), do: true
  defp constrained_track?({:bounded, _track, _minimum, _maximum}), do: true
  defp constrained_track?(_track), do: false

  defp validate_track!(track) do
    _spec = normalize_track!(track)
    :ok
  end

  defp normalize_track!({:bounded, track, minimum, maximum}) do
    minimum = non_negative_integer!(minimum, :min)
    maximum = maximum!(maximum, :max)
    spec = normalize_base_track!(track)
    minimum = max(minimum, spec.min)

    if maximum != :infinity and minimum > maximum do
      raise ArgumentError, "minimum size cannot be greater than maximum size"
    end

    %{spec | min: minimum, max: maximum}
  end

  defp normalize_track!(track),
    do: normalize_base_track!(track)

  defp normalize_base_track!(size) when is_integer(size) and size >= 0,
    do: %{kind: :fixed, value: size, weight: 0.0, min: 0, max: :infinity}

  defp normalize_base_track!(:fill),
    do: %{kind: :flexible, value: 0, weight: 1.0, min: 0, max: :infinity}

  defp normalize_base_track!({:weight, weight}) when is_number(weight) and weight > 0,
    do: %{kind: :flexible, value: 0, weight: weight * 1.0, min: 0, max: :infinity}

  defp normalize_base_track!({:percentage, value})
       when is_number(value) and value >= 0 and value <= 100,
       do: %{kind: :percentage, value: value, weight: 0.0, min: 0, max: :infinity}

  defp normalize_base_track!(track),
    do: raise(ArgumentError, "invalid layout track: #{inspect(track)}")

  defp request_priority(%{kind: :fixed}), do: 0
  defp request_priority(%{kind: :percentage}), do: 1

  defp requested_size(%{kind: :fixed, value: value}, _available), do: value

  defp requested_size(%{kind: :percentage, value: value}, available),
    do: round(available * value / 100)

  defp clamp(value, minimum, :infinity), do: max(value, minimum)
  defp clamp(value, minimum, maximum), do: value |> max(minimum) |> min(maximum)
  defp below_maximum?(_value, :infinity), do: true
  defp below_maximum?(value, maximum), do: value < maximum
  defp cap_addition(addition, _current, :infinity), do: addition
  defp cap_addition(addition, current, maximum), do: min(addition, maximum - current)

  defp validate_bound_options!(opts) do
    case Keyword.keys(opts) -- [:min, :max] do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown bound options: #{inspect(unknown)}"
    end
  end

  defp equal_track(origin, length, count, gap, index) do
    available = max(length - gap * max(count - 1, 0), 0)
    size = div(available, count)
    remainder = rem(available, count)
    offset = index * (size + gap) + min(index, remainder)
    track_size = size + if(index < remainder, do: 1, else: 0)
    start = min(origin + offset, origin + length)
    {start, min(track_size, origin + length - start)}
  end

  defp non_negative_integer!(value, _name) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer!(value, name),
    do: raise(ArgumentError, "#{name} must be a non-negative integer, got: #{inspect(value)}")

  defp positive_integer!(value, _name) when is_integer(value) and value > 0, do: value

  defp positive_integer!(value, name),
    do: raise(ArgumentError, "#{name} must be a positive integer, got: #{inspect(value)}")

  defp maximum!(:infinity, _name), do: :infinity
  defp maximum!(value, name), do: non_negative_integer!(value, name)
end
