# assets/ - put your art here

The game looks for these files. Every file is optional: if it is missing, the
game keeps its simple built-in look. Upload files with the exact names below.
Models should be `.glb` (glTF binary). Textures can be `.jpg`, `.png` or `.webp`.

## Models (`assets/models/`)

| File | Used for |
|---|---|
| `car_1.glb` | the cars you drive, and AI traffic (first model) |
| `car_2.glb` ... `car_6.glb` | more AI traffic and police cars (used in turn) |
| `ambulance.glb` | ambulance that comes to crashes |
| `fire_truck.glb` | fire truck that comes to crashes |

Models are fitted automatically: scaled to car length (4.4 m, ambulance 5.2 m,
fire truck 7 m), turned to drive forward, centred and put on the ground. If the
cars drive backwards, tell me and flip `MC_CAR_FLIP` to `true`
(in `scripts/mad_city_assets.gd` and `scripts/vehicle_mc.gd`).

## Textures (`assets/textures/`)

| File | Used for |
|---|---|
| `ground_albedo` | grass / ground outside the city |
| `ground_normal` | optional normal map for the ground |
| `city_albedo` | roads, sidewalks and building walls (one texture for all) |
| `city_normal` | optional normal map for the city |

Pick tileable (seamless) textures, 1024 px or smaller so the phone does not lag.
Good free sources: ambientCG (textures), Kenney and Quaternius (models), all CC0.

## Not hooked up yet

People, helicopter and individual buildings still use the built-in models.
Tell me which of these you uploaded and I will add the hook.
