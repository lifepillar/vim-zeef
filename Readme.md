# Zeef

Zeef is a minimalist dynamic interactive filter for a list of items. It is
used by invoking `zeef#open()`. Zeef does not define any command or mapping.
The arguments of the function are:

1. A list of items;
2. The name of a callback function;
3. The text for the command line prompt.

Try it:

```vim
fun Callback(result)
  echo a:result
endf

call zeef#open(['Jan', 'Jun', 'Jul'], 'Callback', 'Choose')
```

Start typing to filter the list. Press Enter to invoke the callback with the
selected item(s) (multiple selections are possible—see below). Press Esc to
cancel. This is the complete list of keys you can use when the Zeef buffer is
open (these can be customized with `g:zeef_keymap`):

- CTRL-K or up arrow: move up one line;
- CTRL-J or down arrow: move down one line;
- left and right arrows: scroll horizontally;
- CTRL-B, CTRL-F, CTRL-D, CTRL-U, CTRL-E, CTRL-Y: usual movements;
- CTRL-L: clear the prompt;
- CTRL-Z: select/deselect the current line;
- Esc: close Zeef without performing any action;
- Enter: accept the current choice;
- CTRL-S, CTRL-V, CTRL-T: like Enter, but also open a split, vertical split or
  tab.

How does Zeef differ from the several similar plugins already out there, you
ask? The implementation is likely *the simplest possible*: as you type,
`:global` is used to remove the lines that do not match what you are typing.
When you press backspace, `:undo` is used to restore the previous state. Yes,
the core of this plugin is based on just those two Vim commands. It works
surprisingly well, unless your list is huge (hundreds of thousands of lines).

What can you do with Zeef? Whatever you want! Zeef is not bloated with
features that you will never use: it is for people who wish to implement their
own functionality with minimal help. That said, Zeef does come with a few
"sample applications":

- a buffer switcher;
- a path filter;
- a quickfix/location list filter;
- a color scheme selector;
- a buffer tag chooser.

For example, to switch buffer:

```vim
:call zeef#buffer({'unlisted': 0})
```

To populate the arglist with paths selected from the current directory:

```vim
:call zeef#files()
```

To browse `v:oldfiles`:

```vim
:call zeef#args(v:oldfiles)
```

To change the color scheme:

```vim
:call zeef#colorscheme()
```

Use the source code as the authoritative reference. It's not that complicated.

Ah, before you ask: the answer is no. Zeef does *not* perform fuzzy search,
approximate search, match rankings, or other esoteric stuff. All that is out
of the scope of this project. Those are features that are well covered by
other plugins, after all.
