defmodule TermUI.Application do
  @moduledoc false

  def run, do: send(self(), :autodetected_run)
end

defmodule TermUI.TaskFixture do
  @moduledoc false

  def execute, do: send(self(), :explicit_run)
end

defmodule Mix.Tasks.Termui.RunTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Termui.Run

  setup do
    Mix.Task.reenable("compile")
    :ok
  end

  test "runs an explicit module and function" do
    assert :explicit_run = Run.run(["--module", "TermUI.TaskFixture", "--function", "execute"])
    assert_receive :explicit_run
  end

  test "detects the application module from the Mix app name" do
    assert :autodetected_run = Run.run([])
    assert_receive :autodetected_run
  end
end
