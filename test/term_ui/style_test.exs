defmodule TermUI.StyleTest do
  use ExUnit.Case, async: true

  alias TermUI.Style

  describe "new/0" do
    test "creates style with nil colors and empty attrs" do
      style = Style.new()
      assert style.fg == nil
      assert style.bg == nil
      assert MapSet.size(style.attrs) == 0
    end
  end

  describe "from/1" do
    test "creates style from keyword list" do
      style = Style.from(fg: :blue, bg: :white, bold: true)
      assert style.fg == :blue
      assert style.bg == :white
      assert Style.has_attr?(style, :bold)
    end

    test "creates style from map" do
      style = Style.from(%{fg: :red, italic: true})
      assert style.fg == :red
      assert Style.has_attr?(style, :italic)
    end

    test "ignores false attribute values" do
      style = Style.from(bold: false, underline: true)
      refute Style.has_attr?(style, :bold)
      assert Style.has_attr?(style, :underline)
    end

    test "accepts attrs as MapSet" do
      style = Style.from(attrs: [:bold, :italic])
      assert Style.has_attr?(style, :bold)
      assert Style.has_attr?(style, :italic)
    end
  end

  describe "color setters" do
    test "fg/2 sets foreground color" do
      style = Style.new() |> Style.fg(:blue)
      assert style.fg == :blue
    end

    test "bg/2 sets background color" do
      style = Style.new() |> Style.bg(:white)
      assert style.bg == :white
    end

    test "supports named colors" do
      style = Style.new() |> Style.fg(:bright_cyan)
      assert style.fg == :bright_cyan
    end

    test "supports indexed colors" do
      style = Style.new() |> Style.fg({:indexed, 196})
      assert style.fg == {:indexed, 196}
    end

    test "supports RGB colors" do
      style = Style.new() |> Style.fg({:rgb, 255, 128, 0})
      assert style.fg == {:rgb, 255, 128, 0}
    end

    test "supports :default color" do
      style = Style.new() |> Style.fg(:default)
      assert style.fg == :default
    end
  end

  describe "attribute setters" do
    test "bold/1 adds bold attribute" do
      style = Style.new() |> Style.bold()
      assert Style.has_attr?(style, :bold)
    end

    test "dim/1 adds dim attribute" do
      style = Style.new() |> Style.dim()
      assert Style.has_attr?(style, :dim)
    end

    test "italic/1 adds italic attribute" do
      style = Style.new() |> Style.italic()
      assert Style.has_attr?(style, :italic)
    end

    test "underline/1 adds underline attribute" do
      style = Style.new() |> Style.underline()
      assert Style.has_attr?(style, :underline)
    end

    test "blink/1 adds blink attribute" do
      style = Style.new() |> Style.blink()
      assert Style.has_attr?(style, :blink)
    end

    test "reverse/1 adds reverse attribute" do
      style = Style.new() |> Style.reverse()
      assert Style.has_attr?(style, :reverse)
    end

    test "hidden/1 adds hidden attribute" do
      style = Style.new() |> Style.hidden()
      assert Style.has_attr?(style, :hidden)
    end

    test "strikethrough/1 adds strikethrough attribute" do
      style = Style.new() |> Style.strikethrough()
      assert Style.has_attr?(style, :strikethrough)
    end

    test "multiple attributes can be combined" do
      style = Style.new() |> Style.bold() |> Style.italic() |> Style.underline()
      assert Style.has_attr?(style, :bold)
      assert Style.has_attr?(style, :italic)
      assert Style.has_attr?(style, :underline)
    end
  end

  describe "remove_attr/2" do
    test "removes an attribute" do
      style = Style.new() |> Style.bold() |> Style.remove_attr(:bold)
      refute Style.has_attr?(style, :bold)
    end

    test "removing non-existent attribute is safe" do
      style = Style.new() |> Style.remove_attr(:bold)
      refute Style.has_attr?(style, :bold)
    end
  end

  describe "clear_attrs/1" do
    test "removes all attributes" do
      style = Style.new() |> Style.bold() |> Style.italic() |> Style.clear_attrs()
      assert MapSet.size(style.attrs) == 0
    end
  end

  describe "has_attr?/2" do
    test "returns true when attribute present" do
      style = Style.new() |> Style.bold()
      assert Style.has_attr?(style, :bold)
    end

    test "returns false when attribute absent" do
      style = Style.new()
      refute Style.has_attr?(style, :bold)
    end
  end

  describe "merge/2" do
    test "override style replaces nil values" do
      base = Style.new() |> Style.fg(:blue)
      override = Style.new() |> Style.bg(:white)
      merged = Style.merge(base, override)

      assert merged.fg == :blue
      assert merged.bg == :white
    end

    test "override style replaces non-nil values" do
      base = Style.new() |> Style.fg(:blue)
      override = Style.new() |> Style.fg(:red)
      merged = Style.merge(base, override)

      assert merged.fg == :red
    end

    test "attributes are combined" do
      base = Style.new() |> Style.bold()
      override = Style.new() |> Style.italic()
      merged = Style.merge(base, override)

      assert Style.has_attr?(merged, :bold)
      assert Style.has_attr?(merged, :italic)
    end

    test "merge preserves base when override is nil" do
      base = Style.new() |> Style.fg(:blue) |> Style.bg(:white)
      override = Style.new()
      merged = Style.merge(base, override)

      assert merged.fg == :blue
      assert merged.bg == :white
    end
  end

  describe "inherit/2" do
    test "fills nil values from parent" do
      child = Style.new() |> Style.fg(:blue)
      parent = Style.new() |> Style.bg(:white)
      effective = Style.inherit(child, parent)

      assert effective.fg == :blue
      assert effective.bg == :white
    end

    test "child values take precedence" do
      child = Style.new() |> Style.fg(:blue)
      parent = Style.new() |> Style.fg(:red)
      effective = Style.inherit(child, parent)

      assert effective.fg == :blue
    end

    test "inherits parent attrs when child has none" do
      child = Style.new() |> Style.fg(:blue)
      parent = Style.new() |> Style.bold() |> Style.italic()
      effective = Style.inherit(child, parent)

      assert Style.has_attr?(effective, :bold)
      assert Style.has_attr?(effective, :italic)
    end

    test "child attrs override when present" do
      child = Style.new() |> Style.underline()
      parent = Style.new() |> Style.bold()
      effective = Style.inherit(child, parent)

      assert Style.has_attr?(effective, :underline)
      refute Style.has_attr?(effective, :bold)
    end
  end

  describe "reset/1" do
    test "returns new empty style" do
      style = Style.new() |> Style.fg(:blue) |> Style.bold()
      reset_style = Style.reset(style)

      assert reset_style.fg == nil
      assert reset_style.bg == nil
      assert MapSet.size(reset_style.attrs) == 0
    end
  end

  describe "get_variant/2" do
    test "returns requested variant" do
      variants = %{
        normal: Style.new() |> Style.fg(:white),
        focused: Style.new() |> Style.fg(:blue)
      }

      style = Style.get_variant(variants, :focused)
      assert style.fg == :blue
    end

    test "falls back to normal when variant not found" do
      variants = %{
        normal: Style.new() |> Style.fg(:white)
      }

      style = Style.get_variant(variants, :focused)
      assert style.fg == :white
    end

    test "returns new style when no variants found" do
      variants = %{}
      style = Style.get_variant(variants, :focused)
      assert style.fg == nil
    end
  end

  describe "create_variant/2" do
    test "merges normal with variant" do
      normal = Style.new() |> Style.fg(:white) |> Style.bold()
      variant = Style.new() |> Style.fg(:blue)
      result = Style.create_variant(normal, variant)

      assert result.fg == :blue
      assert Style.has_attr?(result, :bold)
    end
  end

  describe "build_variants/1" do
    test "builds complete variant map with inheritance" do
      variants =
        Style.build_variants(%{
          normal: Style.new() |> Style.fg(:white) |> Style.bold(),
          focused: Style.new() |> Style.fg(:blue),
          disabled: Style.new() |> Style.fg(:bright_black)
        })

      # Normal unchanged
      assert variants.normal.fg == :white
      assert Style.has_attr?(variants.normal, :bold)

      # Focused inherits bold from normal
      assert variants.focused.fg == :blue
      assert Style.has_attr?(variants.focused, :bold)

      # Disabled inherits bold from normal
      assert variants.disabled.fg == :bright_black
      assert Style.has_attr?(variants.disabled, :bold)
    end

    test "creates normal when not provided" do
      variants =
        Style.build_variants(%{
          focused: Style.new() |> Style.fg(:blue)
        })

      assert variants.focused.fg == :blue
    end
  end

  describe "to_rgb/1" do
    test "returns RGB tuple unchanged" do
      assert Style.to_rgb({:rgb, 128, 64, 32}) == {128, 64, 32}
    end

    test "converts named colors to RGB" do
      assert Style.to_rgb(:black) == {0, 0, 0}
      assert Style.to_rgb(:red) == {128, 0, 0}
      assert Style.to_rgb(:bright_red) == {255, 0, 0}
      assert Style.to_rgb(:white) == {192, 192, 192}
      assert Style.to_rgb(:bright_white) == {255, 255, 255}
    end

    test "converts indexed colors to RGB" do
      # Standard colors (0-15)
      assert Style.to_rgb({:indexed, 0}) == {0, 0, 0}
      assert Style.to_rgb({:indexed, 1}) == {128, 0, 0}

      # Color cube (16-231)
      assert Style.to_rgb({:indexed, 16}) == {0, 0, 0}
      assert Style.to_rgb({:indexed, 196}) == {255, 0, 0}

      # Grayscale (232-255)
      {r, g, b} = Style.to_rgb({:indexed, 232})
      assert r == g and g == b
    end

    test "converts :default to white" do
      assert Style.to_rgb(:default) == {255, 255, 255}
    end
  end

  describe "rgb_to_indexed/1" do
    test "converts grayscale to grayscale range" do
      # Pure gray should map to grayscale
      idx = Style.rgb_to_indexed({128, 128, 128})
      assert idx >= 232 or idx == 16 or idx == 231
    end

    test "converts colors to color cube" do
      # Pure red
      idx = Style.rgb_to_indexed({255, 0, 0})
      # Should be in color cube range (16-231)
      assert idx >= 16 and idx <= 231
    end

    test "converts black correctly" do
      idx = Style.rgb_to_indexed({0, 0, 0})
      # Very dark should map to black
      assert idx == 16
    end

    test "converts near-white to appropriate index" do
      idx = Style.rgb_to_indexed({255, 255, 255})
      # Should map to white
      assert idx == 231
    end
  end

  describe "to_named/1" do
    test "returns named colors unchanged" do
      assert Style.to_named(:red) == :red
      assert Style.to_named(:bright_cyan) == :bright_cyan
    end

    test "converts :default to :white" do
      assert Style.to_named(:default) == :white
    end

    test "converts RGB to nearest named color" do
      # Pure red
      assert Style.to_named({:rgb, 255, 0, 0}) == :bright_red
      # Pure blue
      assert Style.to_named({:rgb, 0, 0, 255}) == :bright_blue
      # Dark gray
      nearest = Style.to_named({:rgb, 100, 100, 100})
      assert nearest in [:bright_black, :white]
    end

    test "converts indexed to nearest named color" do
      # Red from color cube
      assert Style.to_named({:indexed, 196}) == :bright_red
    end
  end

  describe "convert_for_terminal/2" do
    test "true_color returns color unchanged" do
      color = {:rgb, 128, 64, 32}
      assert Style.convert_for_terminal(color, :true_color) == color
    end

    test "color_256 converts RGB to indexed" do
      color = {:rgb, 255, 0, 0}
      result = Style.convert_for_terminal(color, :color_256)
      assert {:indexed, _} = result
    end

    test "color_256 preserves named colors" do
      assert Style.convert_for_terminal(:red, :color_256) == :red
    end

    test "color_256 preserves indexed colors" do
      color = {:indexed, 196}
      assert Style.convert_for_terminal(color, :color_256) == color
    end

    test "color_16 converts to named colors" do
      assert Style.convert_for_terminal({:rgb, 255, 0, 0}, :color_16) == :bright_red
      assert Style.convert_for_terminal({:indexed, 196}, :color_16) == :bright_red
    end
  end

  describe "semantic/1" do
    test "returns primary color" do
      assert Style.semantic(:primary) == :blue
    end

    test "returns secondary color" do
      assert Style.semantic(:secondary) == :cyan
    end

    test "returns success color" do
      assert Style.semantic(:success) == :green
    end

    test "returns warning color" do
      assert Style.semantic(:warning) == :yellow
    end

    test "returns error color" do
      assert Style.semantic(:error) == :red
    end

    test "returns info color" do
      assert Style.semantic(:info) == :cyan
    end

    test "returns muted color" do
      assert Style.semantic(:muted) == :bright_black
    end

    test "returns default for unknown semantic" do
      assert Style.semantic(:unknown) == :default
    end
  end

  describe "builder pattern" do
    test "supports fluent chaining" do
      style =
        Style.new()
        |> Style.fg(:blue)
        |> Style.bg(:white)
        |> Style.bold()
        |> Style.underline()

      assert style.fg == :blue
      assert style.bg == :white
      assert Style.has_attr?(style, :bold)
      assert Style.has_attr?(style, :underline)
    end

    test "immutability is preserved" do
      original = Style.new()
      modified = Style.fg(original, :blue)

      assert original.fg == nil
      assert modified.fg == :blue
    end
  end

  describe "edge cases" do
    test "handles empty MapSet in attrs" do
      style = %Style{fg: nil, bg: nil, attrs: MapSet.new()}
      assert MapSet.size(style.attrs) == 0
    end

    test "handles duplicate attribute additions" do
      style = Style.new() |> Style.bold() |> Style.bold()
      assert MapSet.size(style.attrs) == 1
    end

    test "handles all 16 named colors" do
      colors = [
        :black,
        :red,
        :green,
        :yellow,
        :blue,
        :magenta,
        :cyan,
        :white,
        :bright_black,
        :bright_red,
        :bright_green,
        :bright_yellow,
        :bright_blue,
        :bright_magenta,
        :bright_cyan,
        :bright_white
      ]

      for color <- colors do
        style = Style.new() |> Style.fg(color)
        assert style.fg == color

        {r, g, b} = Style.to_rgb(color)
        assert r >= 0 and r <= 255
        assert g >= 0 and g <= 255
        assert b >= 0 and b <= 255
      end
    end
  end

  test "option construction and cell conversion preserve all visible values" do
    style =
      Style.from(
        fg: {:rgb, 1, 2, 3},
        bg: {:indexed, 42},
        dim: true,
        blink: true,
        reverse: true,
        hidden: true,
        strikethrough: true
      )

    for attribute <- [:dim, :blink, :reverse, :hidden, :strikethrough] do
      assert Style.has_attr?(style, attribute)
    end

    assert Style.equal?(
             style,
             Style.from(
               style
               |> Map.from_struct()
               |> Map.delete(:attrs)
               |> Map.put(:attrs, style.attrs)
             )
           )

    refute Style.empty?(style)
    assert Style.empty?(Style.new())

    cell = Style.to_cell(style, "界")
    assert cell.fg == {1, 2, 3}
    assert cell.bg == 42
    assert cell.char == "界"
  end
end
