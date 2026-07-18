# ReRoom Hero Room Setup Guide

**Document version:** 1.2  
**Date:** 2026-07-18  
**Status:** Working guide — ready for branch review  
**Workspace:** P3/P4 Product & Demo  

## Purpose

This guide explains how to prepare a physical room before a ReRoom capture, device test, regression run, or demo recording.

It is a reusable procedure. Facts about the selected room, target, measurements, photographs, and approval decision belong in the separate `room-setup.md` record.

This guide does not redefine canonical product requirements or authorize product implementation.

---

## 1. Choose the room and target

Use one controlled room that the team can access repeatedly until submission.

Choose one target:

- a freestanding armchair; or
- a small solid table.

Prefer a target that:

- has a clear, solid outline;
- is not transparent;
- is not strongly reflective;
- has visible floor around it;
- can be viewed from the front and at least one side;
- can remain in approximately the same position;
- leaves enough space for slow, safe camera movement.

Avoid thin open-frame chairs, glass furniture, mirrors, and heavily reflective objects when a simpler target is available.

---

## 2. Prepare the main background

Use an opaque, matte wall or another visually simple surface as the target's main background.

The room may contain glass walls, but:

- the glass should not be the main background behind the target;
- reflections and people moving behind the glass should be minimized;
- the supported camera route should keep the opaque background behind the target whenever possible.

Do not place the target directly against the wall unless a capture test shows that this is necessary. Leave enough clearance to observe floor and wall around it.

Remove or hide:

- people and pets;
- private screens;
- passwords or access details;
- personal documents and photographs;
- moving objects;
- unnecessary visual clutter.

---

## 3. Clear the test area

Remove non-essential objects from the immediate test area:

- bags;
- cables;
- bottles;
- loose chairs;
- boxes;
- clothing;
- trip hazards.

There is no mandatory fixed empty radius. The goal is enough clear space to:

- see floor around the target;
- approach the target safely;
- follow the planned route;
- keep the target visible during most of the movement.

Record any unavoidable foreground object because it may affect later occlusion tests.

---

## 4. Establish reproducible lighting

Use lighting that can be reproduced during later tests.

Prefer:

- stable ceiling or ambient lights;
- no strong backlight;
- no direct glare on the target;
- no rapidly changing daylight.

Record:

- the main light sources;
- whether daylight is present;
- approximate time of day when relevant;
- any setting that should remain unchanged.

The room does not need laboratory-identical lighting. It should be stable enough that software changes can be distinguished from environmental changes.

---

## 5. Measure the physical target

Measure to the nearest centimetre where practical:

- width or diameter;
- depth;
- height;
- distance from the nearest target edge to the wall;
- candidate starting-position distance to the target centre.

Record uncertainty when a curved or irregular shape makes a measurement approximate.

Published dimensions may be used for virtual catalogue assets, but the selected real target should be measured directly.

---

## 6. Take setup photographs

Store original photographs in the restricted team drive, not in GitHub.

Recommended setup evidence:

1. target-front view;
2. target-area overview;
3. side or 45-degree target view;
4. optional measurement evidence.

Check every image for:

- people;
- screens;
- credentials;
- personal documents;
- identifying information.

A route photograph is not required until the first capture build has established a useful starting position and supported path.

---

## 7. Establish the route after the first capture test

Create a provisional `START-A` position before the first test, but do not freeze the route until the app has been tried in the room.

After the first successful test:

1. confirm the useful starting distance;
2. confirm the supported movement path;
3. mark the target base position with removable tape;
4. mark `START-A`;
5. optionally mark intermediate positions;
6. photograph the final markers.

Recommended operation:

- phone around chest height;
- slow, smooth movement;
- target visible for most of the route;
- avoid framing the target mainly against glass.

A significant setup change after approval creates a new room revision such as `ROOM-r02`.

---

## 8. Before every live test

- [ ] Correct room revision confirmed
- [ ] Correct target confirmed
- [ ] Target position matches the approved setup
- [ ] Floor around the target is visible
- [ ] Movement area is clear
- [ ] Lighting matches the documented setup
- [ ] No people or personal data are visible
- [ ] Device is charged
- [ ] Build and commit SHA are recorded
- [ ] Evidence storage is ready
- [ ] Screen recording is ready when required

---

## 9. Approval

Use these statuses:

- `PROVISIONAL`
- `APPROVED WITH CHANGES`
- `APPROVED`
- `REJECTED`

A room becomes `APPROVED` only after:

- the target and route are physically safe;
- the room can be accessed repeatedly;
- the first relevant capture build can record the setup;
- the team confirms that the setup is suitable for the intended test.

---

## 10. Limitations

- This setup supports a controlled prototype scenario, not arbitrary-room support.
- Photographs document the setup; they are not substitutes for ARKit capture.
- The official `.rrcap` fixture can only be created through the ReRoom capture implementation.
- Do not describe prerecorded replay as live.
- Do not claim replacement or removal works until the relevant build and evidence pass.
