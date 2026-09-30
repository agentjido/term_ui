defmodule TermUI.DisplayWidthTest do
  use ExUnit.Case, async: true

  alias TermUI.DisplayWidth

  describe "width/1" do
    test "ASCII characters are single-width" do
      assert DisplayWidth.width("A") == 1
      assert DisplayWidth.width("z") == 1
      assert DisplayWidth.width("0") == 1
      assert DisplayWidth.width("@") == 1
    end

    test "space is single-width" do
      assert DisplayWidth.width(" ") == 1
    end

    test "CJK characters are double-width" do
      assert DisplayWidth.width("日") == 2
      assert DisplayWidth.width("本") == 2
      assert DisplayWidth.width("語") == 2
      assert DisplayWidth.width("中") == 2
      assert DisplayWidth.width("文") == 2
    end

    test "Hiragana is double-width" do
      assert DisplayWidth.width("あ") == 2
      assert DisplayWidth.width("い") == 2
    end

    test "Katakana is double-width" do
      assert DisplayWidth.width("ア") == 2
      assert DisplayWidth.width("イ") == 2
    end

    test "Hangul is double-width" do
      assert DisplayWidth.width("한") == 2
      assert DisplayWidth.width("글") == 2
    end

    test "combining characters are zero-width" do
      # Combining acute accent
      assert DisplayWidth.width("\u0301") == 0
      # Combining grave accent
      assert DisplayWidth.width("\u0300") == 0
    end

    test "zero-width characters" do
      # Zero Width Space
      assert DisplayWidth.width("\u200B") == 0
      # Zero Width Joiner
      assert DisplayWidth.width("\u200D") == 0
    end

    test "control characters are zero-width" do
      # NULL
      assert DisplayWidth.width(<<0>>) == 0
      # BEL
      assert DisplayWidth.width(<<7>>) == 0
    end

    test "grapheme with combining character" do
      # e + combining acute = é (should be 1 width total)
      assert DisplayWidth.width("e\u0301") == 1
    end

    test "emoji are double-width" do
      assert DisplayWidth.width("😀") == 2
      assert DisplayWidth.width("🎉") == 2
    end

    test "fullwidth forms are double-width" do
      # Fullwidth A
      assert DisplayWidth.width("Ａ") == 2
    end

    test "C1 control characters are zero-width" do
      # C1 controls in valid UTF-8 encoding (U+0080 to U+009F)
      # These are valid UTF-8 two-byte sequences
      assert DisplayWidth.width("\u0080") == 0
      assert DisplayWidth.width("\u009F") == 0
    end

    test "DEL character is zero-width" do
      assert DisplayWidth.width(<<127>>) == 0
    end

    test "combining diacritical marks extended" do
      # U+1AB0 - Combining Doubled Circumflex Accent
      assert DisplayWidth.width("\u1AB0") == 0
    end

    test "combining diacritical marks supplement" do
      # U+1DC0 - Combining Dotted Grave Accent
      assert DisplayWidth.width("\u1DC0") == 0
    end

    test "combining diacritical marks for symbols" do
      # U+20D0 - Combining Left Harpoon Above
      assert DisplayWidth.width("\u20D0") == 0
    end

    test "combining half marks" do
      # U+FE20 - Combining Ligature Left Half
      assert DisplayWidth.width("\uFE20") == 0
    end

    test "word joiner is zero-width" do
      # U+2060 - Word Joiner
      assert DisplayWidth.width("\u2060") == 0
    end

    test "BOM is zero-width" do
      # U+FEFF - Zero Width No-Break Space (BOM)
      assert DisplayWidth.width("\uFEFF") == 0
    end

    test "CJK radicals supplement" do
      # U+2E80 - CJK Radical Repeat
      assert DisplayWidth.width("\u2E80") == 2
    end

    test "CJK symbols and punctuation" do
      # U+3001 - Ideographic Comma
      assert DisplayWidth.width("\u3001") == 2
      # U+3000 - Ideographic Space
      assert DisplayWidth.width("\u3000") == 2
    end

    test "Bopomofo characters" do
      # U+3100 - Bopomofo Letter B
      assert DisplayWidth.width("\u3100") == 2
    end

    test "Hangul Jamo" do
      # U+1100 - Hangul Choseong Kiyeok
      assert DisplayWidth.width("\u1100") == 2
    end

    test "CJK compatibility ideographs" do
      # U+F900 - CJK Compatibility Ideograph
      assert DisplayWidth.width("\uF900") == 2
    end

    test "fullwidth currency symbols" do
      # U+FFE0 - Fullwidth Cent Sign
      assert DisplayWidth.width("\uFFE0") == 2
      # U+FFE1 - Fullwidth Pound Sign
      assert DisplayWidth.width("\uFFE1") == 2
    end

    test "transport and map symbols emoji" do
      # U+1F680 - Rocket
      assert DisplayWidth.width("🚀") == 2
    end

    test "supplemental symbols and pictographs" do
      # U+1F900 range
      assert DisplayWidth.width("🤖") == 2
    end

    test "Latin extended characters are single-width" do
      # Accented characters (precomposed)
      assert DisplayWidth.width("é") == 1
      assert DisplayWidth.width("ñ") == 1
      assert DisplayWidth.width("ü") == 1
    end

    test "Greek characters are single-width" do
      assert DisplayWidth.width("α") == 1
      assert DisplayWidth.width("Ω") == 1
    end

    test "Cyrillic characters are single-width" do
      assert DisplayWidth.width("Д") == 1
      assert DisplayWidth.width("я") == 1
    end

    test "Arabic characters are single-width" do
      assert DisplayWidth.width("ع") == 1
    end

    test "Hebrew characters are single-width" do
      assert DisplayWidth.width("א") == 1
    end

    test "Thai characters are single-width" do
      assert DisplayWidth.width("ก") == 1
    end
  end

  describe "string_width/1" do
    test "ASCII string" do
      assert DisplayWidth.string_width("Hello") == 5
      assert DisplayWidth.string_width("World") == 5
    end

    test "empty string" do
      assert DisplayWidth.string_width("") == 0
    end

    test "CJK string" do
      assert DisplayWidth.string_width("日本語") == 6
      assert DisplayWidth.string_width("中文") == 4
    end

    test "mixed width string" do
      # "A" (1) + "日" (2) + "B" (1) = 4
      assert DisplayWidth.string_width("A日B") == 4
    end

    test "string with combining characters" do
      # "Cafe" + combining acute = 4 width (combining char is zero-width)
      assert DisplayWidth.string_width("Cafe\u0301") == 4
    end

    test "string with precomposed characters" do
      # Café with precomposed é (U+00E9) = 4 chars, 4 width
      assert DisplayWidth.string_width("Café") == 4
    end

    test "emoji string" do
      assert DisplayWidth.string_width("😀😀") == 4
    end

    test "string with control characters" do
      # Hello with embedded NULL and BEL (zero-width)
      assert DisplayWidth.string_width("Hel" <> <<0>> <> "lo") == 5
    end

    test "long mixed international string" do
      # "Hello" (5) + "世界" (4) + "!" (1) = 10
      assert DisplayWidth.string_width("Hello世界!") == 10
    end

    test "string with multiple combining marks" do
      # a + combining acute + combining tilde = 1 width
      assert DisplayWidth.string_width("a\u0301\u0303") == 1
    end

    test "fullwidth ASCII string" do
      # "ＡＢＣ" - fullwidth ABC = 6 width
      assert DisplayWidth.string_width("ＡＢＣ") == 6
    end

    test "string with zero-width joiners" do
      # Text with ZWJ
      assert DisplayWidth.string_width("a\u200Db") == 2
    end

    test "only zero-width characters" do
      assert DisplayWidth.string_width("\u200B\u200C\u200D") == 0
    end

    test "only combining characters" do
      assert DisplayWidth.string_width("\u0301\u0302\u0303") == 0
    end
  end

  describe "double_width?/1" do
    test "returns true for CJK" do
      assert DisplayWidth.double_width?("日")
      assert DisplayWidth.double_width?("한")
    end

    test "returns false for ASCII" do
      refute DisplayWidth.double_width?("A")
      refute DisplayWidth.double_width?(" ")
    end

    test "returns false for combining characters" do
      refute DisplayWidth.double_width?("\u0301")
    end
  end

  describe "zero_width?/1" do
    test "returns true for combining characters" do
      assert DisplayWidth.zero_width?("\u0301")
      assert DisplayWidth.zero_width?("\u200B")
    end

    test "returns false for regular characters" do
      refute DisplayWidth.zero_width?("A")
      refute DisplayWidth.zero_width?(" ")
    end

    test "returns false for wide characters" do
      refute DisplayWidth.zero_width?("日")
    end
  end

  describe "truncate/2" do
    test "truncates ASCII string" do
      {result, width} = DisplayWidth.truncate("Hello World", 5)
      assert result == "Hello"
      assert width == 5
    end

    test "returns full string if within width" do
      {result, width} = DisplayWidth.truncate("Hi", 10)
      assert result == "Hi"
      assert width == 2
    end

    test "truncates at character boundary for CJK" do
      # "日本語" = 6 width, truncate to 4
      {result, width} = DisplayWidth.truncate("日本語", 4)
      assert result == "日本"
      assert width == 4
    end

    test "doesn't split double-width character" do
      # "日本語" = 6 width, truncate to 5 (can't fit third char)
      {result, width} = DisplayWidth.truncate("日本語", 5)
      assert result == "日本"
      assert width == 4
    end

    test "empty string" do
      {result, width} = DisplayWidth.truncate("", 10)
      assert result == ""
      assert width == 0
    end

    test "zero width" do
      {result, width} = DisplayWidth.truncate("Hello", 0)
      assert result == ""
      assert width == 0
    end

    test "truncate mixed ASCII and CJK" do
      # "AB日C" = 1+1+2+1 = 5 width, truncate to 3
      {result, width} = DisplayWidth.truncate("AB日C", 3)
      assert result == "AB"
      assert width == 2
    end

    test "truncate preserves combining characters" do
      # "Café" with combining é, truncate to 3
      {result, width} = DisplayWidth.truncate("Cafe\u0301", 3)
      assert result == "Caf"
      assert width == 3
    end

    test "truncate emoji string" do
      # Each emoji is width 2
      {result, width} = DisplayWidth.truncate("😀😀😀", 4)
      assert result == "😀😀"
      assert width == 4
    end

    test "truncate with exact fit" do
      {result, width} = DisplayWidth.truncate("Hello", 5)
      assert result == "Hello"
      assert width == 5
    end

    test "truncate width 1 with double-width first char" do
      # Can't fit any character
      {result, width} = DisplayWidth.truncate("日本", 1)
      assert result == ""
      assert width == 0
    end

    test "truncate string with zero-width chars" do
      # "a\u0301b" = 2 width (combining is zero), truncate to 1
      {result, width} = DisplayWidth.truncate("a\u0301b", 1)
      assert result == "a\u0301"
      assert width == 1
    end
  end

  describe "pad/3" do
    test "pads to right by default" do
      result = DisplayWidth.pad("Hi", 5)
      assert result == "Hi   "
    end

    test "pads to left" do
      result = DisplayWidth.pad("Hi", 5, direction: :left)
      assert result == "   Hi"
    end

    test "pads center" do
      result = DisplayWidth.pad("Hi", 6, direction: :center)
      assert result == "  Hi  "
    end

    test "no padding if string meets width" do
      result = DisplayWidth.pad("Hello", 5)
      assert result == "Hello"
    end

    test "no padding if string exceeds width" do
      result = DisplayWidth.pad("Hello", 3)
      assert result == "Hello"
    end

    test "custom padding character" do
      result = DisplayWidth.pad("Hi", 5, char: "-")
      assert result == "Hi---"
    end

    test "handles wide characters" do
      # "日" is width 2, pad to 4
      result = DisplayWidth.pad("日", 4)
      assert result == "日  "
    end

    test "center padding with odd remainder" do
      # 5 - 2 = 3 padding, left gets 1, right gets 2
      result = DisplayWidth.pad("Hi", 5, direction: :center)
      assert result == " Hi  "
    end

    test "pad empty string" do
      result = DisplayWidth.pad("", 5)
      assert result == "     "
    end

    test "pad with CJK string" do
      # "日本" is width 4, pad to 6
      result = DisplayWidth.pad("日本", 6)
      assert result == "日本  "
    end

    test "left pad with wide characters" do
      result = DisplayWidth.pad("日", 4, direction: :left)
      assert result == "  日"
    end

    test "center pad with wide characters" do
      # "日" is width 2, pad to 6, padding = 4
      result = DisplayWidth.pad("日", 6, direction: :center)
      assert result == "  日  "
    end

    test "pad accounts for combining characters" do
      # "e\u0301" is width 1, pad to 3
      result = DisplayWidth.pad("e\u0301", 3)
      assert result == "e\u0301  "
    end

    test "zero target width returns original" do
      result = DisplayWidth.pad("Hello", 0)
      assert result == "Hello"
    end

    test "pad with emoji" do
      # "😀" is width 2, pad to 4
      result = DisplayWidth.pad("😀", 4)
      assert result == "😀  "
    end

    test "pad with custom wide padding character" do
      # Note: String.duplicate counts characters, not display width
      # So padding of 2 characters with "日" gives 2 copies = width 4
      result = DisplayWidth.pad("A", 3, char: "日")
      assert result == "A日日"
      # Display width is actually 1 + 4 = 5, not 3
      # This is a known limitation - pad doesn't account for wide padding chars
    end
  end
end
