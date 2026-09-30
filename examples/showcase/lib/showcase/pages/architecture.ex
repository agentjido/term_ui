defmodule Showcase.Pages.Architecture do
  @moduledoc false

  @behaviour Showcase.Page

  alias Showcase.Layout
  alias TermUI.Widget.MarkdownViewer

  @impl true
  def init, do: MarkdownViewer.init(content: document(), page_size: 20)

  @impl true
  def update(event, state), do: MarkdownViewer.update(event, state)

  @impl true
  def view(state, {width, height}, theme) do
    content = MarkdownViewer.view(state, {max(width - 2, 1), max(height - 2, 1)})
    Layout.panel(content, "Why the seams matter", {width, height}, active: true, theme: theme)
  end

  @impl true
  def help, do: "Arrows scroll this executable architecture guide."

  defp document do
    """
    # TermUI architecture

    The showcase uses the same public contract as an application.

    ## One application owner

    `Showcase.App` owns page selection, theme, dimensions, status, and every
    widget state. A page is a plain module. A page does not start a process or
    a nested runtime.

    ## Pure widget boundary

    ```elixir
    {widget, messages} = Widget.update(event, widget)
    frame = Widget.view(widget, dimensions)
    ```

    Widget messages return to the parent. Clipboard writes become command data.
    A timer requests live data through `Command.async/2`. The command result
    updates application state before the next render.

    ## One frame boundary

    Each page returns one bounded `TermUI.Frame`. The parent composes it with
    the header and footer. The backend receives only the final frame.

    ## One terminal owner

    `TermUI.Backend.Manager` serializes input, resize, drawing, clipboard work,
    and shutdown. Page code cannot write directly to the terminal.

    ## External data

    `Showcase.LiveData` collects local processes, runtime links, VM metrics, and
    connected-node values outside update and view. The BEAM widgets only format
    the snapshots that their parent supplies. Snapshot mode keeps tests and
    documentation output deterministic.
    """
  end
end
