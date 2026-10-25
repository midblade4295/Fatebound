# Fatebound social media kit

Banners and profile icons for the game's social accounts (Kevin: "Give me social media package that has banner and
icon"). Every banner is the painted key art (`art_sources/social/key_art.png`) with the FATEBOUND title, top centre, and
the Knight and the Barbarian clashing under it. `preview.jpg` shows them all.

## X, 0.31.214 (`x/`) -- the 3D set, use these for X
Kevin: "Make me a new X banner and pfp". Made only from renders of the game's own models (no painting): the HD heroes,
the game's world out of focus, the icon's King and throne room; the title in the game's font (`tools/build_x_kit.py`).
| File | Where it goes |
|---|---|
| `x/x_header_1500x500.png` | X header (`x_header_3000x1000.png`: the same, twice the size, for a sharper upload). Five heroes with the King in the middle; FATEBOUND and FAST 5V5 MOBA BATTLES on the left, clear of where X puts your profile picture |
| `x/pfp_king_400.png` (also 800, 1080) | X profile picture: the app icon's King, closer, his face and crown filling X's round crop -- the account looks like the app |
| `x/pfp_knight_*.png`, `x/pfp_stormcaller_*.png` | Two other heroes the same way, if you'd rather |
| `x/preview.jpg` | The header with the King's picture where X puts it, and the three round |

## Banners (`banners/`, 0.31.200: the painted key art)
| File | Where it goes | Notes |
|---|---|---|
| `x_header_1500x500.png` | X (Twitter) header | Your avatar covers the bottom-left corner; nothing important is there |
| `youtube_banner_2560x1440.png` | YouTube channel banner | Phones and computers show only the middle strip (1546 x 423 on phones, the full width on computers); the title and both faces are inside it. TVs show the whole picture. |
| `facebook_cover_1640x624.png` | Facebook page cover | Phones crop the sides; the title and the clash stay in the middle |
| `twitch_banner_1200x480.png` | Twitch profile banner | |
| `discord_server_banner_960x540.png` | Discord server banner | Needs server boost level 2; Discord shows it small, so the title is big |
| `discord_profile_banner_680x240.png` | Discord profile banner | Needs Nitro |
| `share_card_1200x630.png` | Link previews (a website's `og:image`, press, Reddit, Discord embeds) | |
| `key_art_1920x1080.png` | Posts, press kits, video thumbnails, trailers' end card | With the title and "5V5 HERO BATTLES" |
| `key_art_clean_1920x1080.png` | The art alone, as painted (with its crown) | For your own layouts |

## Icons (`icons/`)
| File | Where it goes |
|---|---|
| `avatar_1080.png` | Instagram, TikTok, Facebook profile picture |
| `avatar_800.png` | YouTube profile picture |
| `avatar_512.png` | Discord server icon, Discord avatar |
| `avatar_400.png` | X (Twitter) profile picture |
| `avatar_256.png` | Twitch profile picture, forums |
| `icon_square_1024.png` | Anywhere that wants the game's icon at full size (it's the app icon) |
| `logo_transparent_1400.png`, `logo_transparent_700.png` | The FATEBOUND title with a see-through background, to lay over your own pictures |

The avatars are the app icon. Sites crop profile pictures round; the crown, both faces and the clash stay inside the
circle.

## Remaking them
`godot/tools/build_social_kit.py` makes all of these from `art_sources/social/key_art.png`, the app icon and the title
logo:

    cd godot && python3 tools/build_social_kit.py --out store-listing/social

Its `LAYOUT` sets each banner's size, which part of the art it shows, and the title's size and place. If a site changes
its sizes, add or change an entry there and run it again.
