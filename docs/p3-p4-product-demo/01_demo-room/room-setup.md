# ReRoom Room Setup Record

**Document version:** 1.2  
**Date:** 2026-07-18  
**Authors:** P3/P4 Team  
**Workspace:** P3/P4 Product & Demo  
**Status:** `PROVISIONAL` — awaiting first relevant ReRoom capture-build test  

## 1. Room identification

- **Room ID:** `ROOM-r01`
- **Location profile:** Indoor campus meeting room
- **Room description:** Meeting room with glass side walls, an opaque central white wall, grey carpet, and stable ceiling lighting
- **Chosen target area:** Floor area directly in front of the central opaque white wall
- **Main target background:** Plain opaque white wall
- **Glass walls present:** Yes, to the left and right of the target area
- **Glass-handling rule:** Keep the white wall as the main target background whenever possible. Minimize reflections and people moving behind the glass during tests.
- **Reason for selecting this room:** Stable artificial lighting, repeated access, movable furniture, a simple white target background, and sufficient visible floor for a controlled prototype test
- **Access available until submission:** Yes
- **Can probably be closed or reserved during testing:** Probably; confirm before final live tests
- **Shared evidence folder:** Restricted team drive; link available to the project team

## 2. Target identification

- **Target ID:** `TARGET-001`
- **Target type:** Round pedestal table
- **Target description:** Small circular table with a blue tabletop, black central pedestal, and wide circular base
- **Shape:** Circular tabletop with one central support
- **Colour:** Blue tabletop; black pedestal and base
- **Material:** Blue laminated or painted tabletop with a black metal pedestal and circular metal base
- **Freestanding:** Yes
- **Transparent:** No
- **Highly reflective:** No obvious strong reflection in the documented setup
- **Visible floor around target:** Yes
- **Main background:** Opaque white wall

### Selection rationale

The table was selected because it has a simple, solid outline, one central support, visible floor around it, and clear contrast against the white wall. It should be easier to select and mask than the thin chairs previously considered.

### Known risks

- Glass side walls may introduce reflections or movement if they enter the main camera view.
- The table is close to the white wall, which may limit observed background behind it during removal.
- Wall sockets and a small wall-mounted device are visible above the target area.
- The supported movement path still needs to be established with the first relevant capture build.

## 3. Physical measurements

Measurements were taken manually.

- **Diameter / width:** 60 cm
- **Depth:** 60 cm
- **Height:** 75 cm
- **Distance from nearest table edge to wall:** 10 cm
- **Candidate `START-A` distance to target centre:** 2.74 m
- **Candidate `START-A` physically marked:** No
- **Measurement method:** Manual tape measure
- **Measurement status:** Recorded
- **Measurement evidence photograph:** Recommended; not required for this provisional record

### Measurements not yet required for the provisional commit

These may be added after the first capture test if useful:

- clear floor distance on the left;
- clear floor distance on the right;
- clear floor distance in front;
- final supported route width.

## 4. Target position

- **Target facing direction:** Not applicable; the circular tabletop and pedestal are visually symmetric
- **Current wall clearance:** 10 cm
- **Target position marked with removable tape:** Not yet
- **Position-freeze status:** Not frozen

After the first relevant capture test confirms the position, mark at least two reference points for the base and photograph the markers. A significant move after approval creates a new room revision such as `ROOM-r02`.

### Provisional concern

The 10 cm wall clearance may need to be increased if the capture or removal test requires more visible floor or wall evidence behind the target.

## 5. Floor and background

- **Floor material:** Grey carpet
- **Floor appearance:** Medium-grey, low-detail carpet texture
- **Floor visible around target:** Yes
- **Background wall:** Opaque white painted wall
- **Glass walls:** Present on both sides of the white wall
- **Baseboard:** Dark-grey baseboard along the wall
- **Objects behind/above target:** Wall sockets and a small wall-mounted device
- **Potential difficulty:** Reflections or background movement when the camera pans too far toward the glass

## 6. Lighting

- **Main light source:** Ceiling-mounted artificial lighting
- **Strong direct daylight in the target view:** No
- **Lighting stability:** Appears suitable for repeatable indoor testing
- **Strong backlight:** No
- **Target shadow:** Visible but not currently severe
- **Recording rule:** Keep the same ceiling lights on and avoid introducing changing external light during a run
- **Still to confirm:** Reflection behaviour on the side glass during the supported movement path

## 7. Candidate movement setup

- **Starting-point ID:** `START-A`
- **Candidate starting distance:** 2.74 m from `START-A` to target centre
- **Starting position marked:** Not yet
- **Route status:** `PENDING FIRST CAPTURE-BUILD TEST`
- **Provisional movement:** Slow, supported partial or half-circle while keeping the white wall as the main background
- **Recommended phone height:** Approximately chest height
- **Recommended movement speed:** Slow and smooth
- **Glass avoidance:** Do not frame the target primarily against the glass walls

The route is intentionally not frozen yet. The first relevant capture build may show that the target position, starting position, or movement path should change.

## 8. Evidence photographs

Original photographs stay in the restricted team drive. GitHub should contain only this non-sensitive record and, if later approved, reduced or sanitized evidence.

### Current evidence

- [x] `room-r01-01-target-front.jpg` — front view against the white wall
- [x] `room-r01-02-target-area-overview.jpg` — target, white wall, glass side walls, lighting, and surrounding floor area
- [x] `room-r01-03-target-side.jpg` — side/45-degree view showing tabletop, pedestal, base, floor, and wall relationship

### Recommended but non-blocking evidence

- [ ] `room-r01-04-measurement.jpg` — tape measure confirming one or more dimensions

### Pending until the first capture test

- [ ] `room-r01-05-route.jpg` — final `START-A` and supported route markers

## 9. Privacy and safety

The current target photographs contain no visible people, private screens, passwords, or personal documents in the main target area.

Before every capture:

- [ ] remove people from the target and glass-background views;
- [ ] hide private screens, documents, credentials, and identifying information;
- [ ] remove bags, loose cables, and unnecessary furniture;
- [ ] confirm that the glass areas do not show passing people;
- [ ] confirm that the movement path is physically safe.

## 10. Suitability assessment

| Criterion | Assessment | Notes |
|---|---|---|
| Target visibility | Good | Strong contrast against white wall |
| Target shape | Good | Circular top and single pedestal |
| Visible floor | Good | Carpet visible around base |
| Main background | Good | Opaque white wall |
| Lighting | Good | Stable ceiling lighting available |
| Repeated access | Good | Available until submission |
| Room control | Provisional | Probably reservable; confirm before final tests |
| Glass reflection risk | Moderate | Must be kept outside main supported framing |
| Movement route | Pending | Requires first capture-build test |
| Privacy/safety | Good with preflight | Raw evidence remains restricted |

## 11. Decision

- **Provisional decision:** `APPROVED WITH CHANGES`
- **Reason:** The target is simple, solid, measurable, and clearly framed against an opaque wall. The room provides stable artificial lighting and repeated access. Final approval depends on the first relevant capture test and a safe supported route.

### Required before final `APPROVED` status

1. Run the first relevant ReRoom capture test in this setup.
2. Confirm or adjust the 10 cm wall clearance.
3. Confirm or adjust the 2.74 m candidate starting position.
4. Mark the final target position and supported route.
5. Confirm that reflections and people behind the glass do not disrupt the supported views.
6. Confirm that the room can be closed or reserved for final testing and recording.

## 12. Revision history

| Revision | Date | Change | Author |
|---|---|---|---|
| `r01` | 2026-07-18 | Initial room, target, measurements, access, and photographic evidence recorded | P3/P4 Team |
