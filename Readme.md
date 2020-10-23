# Zeef

Zeef is a minimalist dynamic interactive filter for a list of items. Think of it
as a ~~poo…~~ wise man's CtrlP. 100% Vim script, pure autoload plugin, it does
not define any command or mapping. It is used by invoking `zeef#open()`. The
arguments of the function are:

1. a list of items;
2. the name of a callback function;
3. the text for the command line prompt.

(The function accepts an optional fourth argument to set up custom key mappings:
see `:help zeef` for the details). Try this "zeef":

```vim
fun Callback(result)
  echo a:result
endf

call zeef#open(['January', 'July', 'Lily', 'Lyric', 'Nucleus'], 'Callback', 'Choose')
```

Start typing to filter the list. You may anchor the pattern at the start or at
the end with `^` and `$`, respectively, and you may use `*` as a glob pattern
(if you do not like it this way, you may write your own filter: see `:help
g:Zeef_regexp`). Press Enter to invoke the callback with the selected item(s)
(multiple selections are possible—see below). Press Esc to cancel. The following
is the complete list of keys you can use when the Zeef buffer is open (these can
be customized with `g:zeef_keymap` or by passing custom mappings to
`zeef#open()`):

- CTRL-K or up arrow: move up one line;
- CTRL-J or down arrow: move down one line;
- left and right arrows: scroll horizontally;
- CTRL-B, CTRL-F, CTRL-D, CTRL-U, CTRL-E, CTRL-Y: usual movements;
- CTRL-L: clear the prompt;
- CTRL-G: clear the prompt and deselect all items;
- CTRL-Z: toggle the selection of the current line;
- CTRL-A: select all currently filtered lines;
- CTRL-R: deselect all currently filtered lines;
- Esc, CTRL-C: close Zeef without performing any action;
- Enter: accept the current choice;
- CTRL-S, CTRL-V, CTRL-T: like Enter, but also open a horizonal split, vertical
  split or tab.

How does Zeef differ from the several similar plugins already out there, you
ask? The implementation is likely *the simplest possible*: as you type,
`:global` is used to remove the lines that do not match what you are typing.
When you press backspace, `:undo` is used to restore the previous state. Yes,
the core of this plugin is based on just those two Vim commands. It works
surprisingly well, unless your list is huge (hundreds of thousands of lines).

What can you do with Zeef? Whatever you want! Zeef is not bloated with
features that you will never use: it is for people who wish to implement their
own functionality with minimal help. That said, Zeef does come with a few
"sample applications" or "zeefs":

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

To choose a color scheme:

```vim
:call zeef#colorscheme()
```

Use the source code as the authoritative reference. It's not that complicated.
And don't forget to read the full (albeit short) documentation: see `:help
zeef.txt`.

Ah, before you ask: the answer is no. Zeef does *not* perform fuzzy search,
approximate search, match rankings, or other esoteric stuff. All that is out
of the scope of this project. Those are features that are well covered by
other plugins, after all.
