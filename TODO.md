# TODO Items

## Poetry + Lsp
I want to have ruff and pyright working, and when I open nvim in a folder, or pointed *at* that folder, for my lsp to find the project root, and for poetry to then be activated so that the lsp stuff is looking in the right environment.

I'm not entirely sure how to make this happen but I think first I should just remove my poetry plugin, turn off autochdir, and any code around path selection, and then just get the lsp working again.

Then I should implement the dir switching for telescope and see if that changes anything.


Then I should try and make my poetry plugin use the lsp root dir somehow instead.
Or, find a way to implement the poetry login in the lsp config so that the lsp always loads first and has a chance to find the root dir.
