Scrolling Textures - adding your own skins
==========================================
Drop texture pairs into this folder (mods/Scrolling Textures/input/).
Start the game: they show up in the settings
(Options > Mod Options > Scrolling Textures > Settings) under their file name.
No restart, no conversion. The files stay in this folder, do not delete them.

Each skin needs two files with the same base name:

  name_df.dds   diffuse (color / pattern)
  name_il.dds   glow (self-illumination)

.texture works instead of .dds, but the content must still be DDS.

A single file without _df/_il (e.g. name.dds) is used for both diffuse and glow.
If name_df / name_il exist as well, those win.

Format: DDS, DXT1 or DXT5, both sides a multiple of 4. Nothing is converted or resized.
Files that do not meet this are skipped; the main menu lists what went wrong.
Make the textures tile seamlessly, otherwise seams show while scrolling.

Same name as an existing skin: your file replaces it.
Removing a skin: delete its two files from this folder.

Optional: world light color and display name. Add an entry to data/variants.json
under "imported", matching the file name in lower case:
  { "id": "name", "name": "My Skin", "color": [r, g, b] }   (values 0..1)
Without it the light is white.

Other sources (a single image, pattern + gradient, color skins from other mods) can be
turned into such pairs with the "Scrolling Textures Converter" add-on, which puts them here.
