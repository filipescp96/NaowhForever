# Forever AH Count

Forever AH Count adds a small Auction House icon and the active quantity in parentheses after learned recipe names in Naowh Forever's profession list. Recipes with no active auctions stay unchanged.

The addon totals item quantities, not auction-stack count. For example, two active stacks containing 5 items each display `10`.

## Profitable & Not Selling filter

Naowh Forever's Filter menu gains a **Profitable & Not Selling** checkbox directly below **Profitable**. It shows only learned recipes that:

- have a positive profit according to Naowh Forever's current craft-price calculation; and
- have no active quantity in Forever AH Count's latest Auction House cache.

Like Naowh's built-in **Profitable** filter, the checkbox is disabled until auction prices have been scanned. An owner-auction update automatically rebuilds the filtered recipe list.

## Keeping counts current

World of Warcraft only exposes the player's complete owner-auction list while the Auction House is available. The addon therefore:

- requests the owner list whenever the Auction House opens;
- replaces its cache whenever that list changes (posting, cancelling, expiring, or selling while the Auction House is open);
- saves the latest counts per character so they remain visible after closing the Auction House or reloading the UI.

After installing the addon, visit the Auction House once to populate the cache. Use `/fahc` to see when it was last updated, or `/fahc refresh` while the Auction House is open to request an immediate refresh.

## Favorite recipes at vendors and trainers

An available recipe or pattern that produces one of your unlearned Naowh Forever favorite crafts gets Naowh's gold favorite star directly after its name:

- profession trainers are marked only when the favorite recipe is currently trainable;
- merchant pattern items are marked while they are in stock;
- already-learned favorites, sold-out patterns, ordinary merchant goods, and the buyback tab are not marked.

The markers update when a merchant or trainer refreshes, when a recipe is learned, and when its favorite state changes.

## Favorite Patterns paging

Naowh Forever's **Favorite Patterns** Auction House panel can scan the complete favorite-pattern list instead of stopping at the first visible rows. It opens idle so no market searches are sent until **Scan** is pressed. The button becomes **Pause** while scanning and **Resume Scan** while paused; pausing preserves completed results and the remaining queue. Already-learned recipes stay excluded, and patterns confirmed to have no active buyout are removed from the panel. Available and unresolved entries use pages of eight rows, navigable with the `<` and `>` buttons or the mouse wheel while hovering the panel.

## Scrollable Shopping List

The Shopping List beside the profession window no longer truncates its Crafts, Materials, or Make First sections. All entries share a clean, scrollbar-free area; hover the list and use the mouse wheel. The title, estimated total, and Clear button remain fixed.

When a selected recipe is already in the Shopping List, its header also shows a compact muted count and shopping-cart icon. The count updates immediately when the recipe is added, increased, decreased, removed, or cleared.

Learned recipes receive small status markers in the left recipe list for shopping-list crafts, crafting-queue crafts, and crafted output already held in bags or bank. Hovering a marker shows its relevant quantity, including separate bag and bank counts.

## Crafting Queue

The profession window's right column is split between the Shopping List and a persistent per-character Crafting Queue. Purchased crafts move into the queue when their auction-house materials are ready. Cheaper crafted prerequisites are listed separately and prepared first; missing vendor materials remain clearly marked with a detailed tooltip and can be added to the Shopping List when appropriate.

Queue rows support quantity changes and removal. **Start Queue** prepares the first available batch, then every **Craft Next** batch requires a fresh player click through Naowh's normal crafting path. Completed batches prepare the next prerequisite or regular craft without automating the protected crafting action.

## Return on investment

Known recipe profits can include ROI, calculated as profit divided by the materials' crafting cost. The recipe list shows `(X% ROI)` after non-negative profits, while the selected recipe shows ROI on its own line, including negative ROI in red. ROI below 10% is grey by default, 10–29% is yellow, and 30% or more is green. **Show ROI** in the Filter menu or Professions settings controls both displays, and is enabled by default. The **ROI Color Thresholds...** entry opens the editable thresholds on the Professions settings page.
