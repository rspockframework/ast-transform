# frozen_string_literal: true

module ASTTransform
  # Line-addressed output: text is placed at absolute line numbers, top to bottom, and the cursor never rewinds.
  # When a placement's target line is already behind the cursor, the text is packed (`; `) onto the current line
  # instead — Ruby lets statements share a physical line, so alignment degrades locally and the next placement
  # whose target is still ahead re-anchors. Knows nothing about Ruby structure or ASTs; callers decide WHAT goes
  # on WHICH line, the layout owns the pad-or-pack mechanics.
  class Layout
    def initialize
      @lines = []
      @sealed = false
    end

    # The line number currently being written; the next fresh line would be +cursor + 1+.
    def cursor
      @lines.size
    end

    # Places +text+ at +target_line+ when the cursor hasn't passed it; otherwise packs onto the current line.
    # Multi-line text advances the cursor by its height. When opening a fresh line, the first line is indented to
    # +column+ — cosmetic only (leading whitespace is never significant in emitted code), but it keeps the artifact
    # visually close to the source. Packed text ignores the column, as do continuation lines (they keep their own
    # relative indentation).
    #
    # +seal+ declares the text's last line unextendable (the caller's property — e.g. it terminates a heredoc,
    # whose terminator must stand alone): a subsequent pack opens a fresh line instead of joining it.
    def place(target_line, text, column: nil, seal: false)
      first, *rest = text.split("\n")

      if target_line && target_line > @lines.size
        @lines << '' while @lines.size < target_line
        @lines[-1] = indented(first, column)
      else
        pack(first)
      end

      @lines.concat(rest)
      @sealed = seal
    end

    # Appends +text+ on a new line unconditionally — for text that must never be `;`-packed after a statement
    # (e.g. keywords).
    def place_on_fresh_line(text)
      @lines << text
      @sealed = false
    end

    # Appends +text+ to the current line with a `; ` separator — unless the current line is sealed, in which case
    # the text opens a fresh line (alignment degrades by one more line; validity is preserved). The last line is
    # never blank here: padding blanks are only created inside +place+, which immediately overwrites the padded
    # line.
    def pack(text)
      if @lines.empty? || @sealed
        @lines << text
      else
        @lines[-1] = "#{@lines.last}; #{text}"
      end
      @sealed = false
    end

    # @return [String] the laid-out text, with a trailing newline.
    def to_source
      "#{@lines.join("\n")}\n"
    end

    private

    def indented(text, column)
      column && column.positive? ? "#{' ' * column}#{text}" : text
    end
  end
end
