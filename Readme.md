# Zeef

Zeef is a pure autoload interactive fuzzy filter for a list of items,
entirely written in Vim 9 script. Zeef requires Vim 9.1 or later, built with
`+popupwin` and `+textprop`.

Remarkable features:

- fuzzy matching (courtesy of Vim's `matchfuzzypos()`);
- single or multiple selections;
- allows or prevents duplicate items in multiple selections;
- mouse support.

Zeef does not define any command or mapping: that is left as a task for the
user. It is used by invoking `zeef.Open()`:

    :call zeef#Open(['January', 'July', 'Julian', 'adjective', 'every'])

Start typing to filter the list. Press Tab to select an item: that will
automatically open the “selected items” popup, which displays the currently
selected items. Press Enter to invoke a callback with the selected item(s), or
with the item under the cursor if nothing was selected. Press Esc to cancel.
The default callback just echoes the selected items.

The following is the complete list of special keys you can use when Zeef is
open:

- CTRL-K or up arrow: move up one line.
- CTRL-J or down arrow: move down one line.
- left and right arrows: scroll horizontally.
- CTRL-B, CTRL-F, CTRL-D, CTRL-U, CTRL-E, CTRL-Y: usual movements.
- Backspace delete one character fromt the prompt.
- CTRL-L: clear the prompt.
- Tab selects the current item.
- Shift-Tab deselects the current item.
- CTRL-X: toggles the selection of the current item.
- CTRL-G: deselects all items.
- CTRL-A: selects all currently filtered lines.
- CTRL-R: deselects all currently filtered lines.
- CTRL-P: toggles the display of the selected items popup.
- CTRL-Z: toggles between exact and fuzzy matching.
- Esc, CTRL-C: closes Zeef without performing any action.
- Enter: accepts the current choice.
- CTRL-S, CTRL-V, CTRL-T: same as Enter, but also open a horizonal split,
  vertical split or tab window, respectively.

Zeef supports using the mouse: you may select and deselect by clicking on an
item, and you may use the mouse to scroll both vertically and horizontally.
These are the supported mouse events:

- `<LeftMouse>`: in the Zeef buffer, selects or deselects an item; in the
  selected items popup, removes an item from the list of selected items.
- `<ScrollWheelUp>`, `<ScrollWheelDown>`: vertical scrolling.
- `<ScrollWheelLeft>`, `<ScrollWheelRight>`: horizontal scrolling.

Any of the previous mappings can be overridden: see `:help zeef-customization`.

How does Zeef differ from the several similar plugins already out there, you
ask? The implementation is likely *the simplest possible*: as you type, Zeef
uses `matchfuzzypos()` to filter the displayed items according to the fuzzy
matches. When you press backspace, `:undo` is used to restore the previous
state. The core of this plugin is just that. It works surprisingly well, unless
your list is very large (hundreds of thousands of lines).

What can you do with Zeef? Whatever you want! Zeef is not bloated with features
that you will never use: it is for people who wish to implement their own
functionality with minimal help. That said, Zeef does come with a few “sample
applications” or “zeefs”:

- a buffer switcher;
- a path filter;
- a quickfix/location list filter;
- a color scheme selector;
- a buffer tag chooser.

For example, to switch buffer:

```vim
:call zeef#BufferSwitcher()
```

To populate the arglist with paths selected from the current directory:

```vim
:call zeef#Files()
```

To browse `v:oldfiles`:

```vim
:call zeef#Args(v:oldfiles)
```

To choose a color scheme:

```vim
:call zeef#ColorschemeSwitcher()
```

Zeef is fully documented: see `:help zeef.txt` for the details.
