# Simulation layers

PetalWild keeps one persistent record per plant, creature, and resident. The picture on screen is a reconstruction of that record, at a fidelity the camera can afford.

| Level | Who | What runs | What this build does |
| --- | --- | --- | --- |
| L0 | Held, inspected, or hero creature | Full deform, face, collision, high-rate audio | The grabbed jelly gets squash, stretch, and a face. One body at a time. |
| L1 | Nearby visitors and residents | Path, needs, animation | Jellies path near their flower. By day Lumen keeps the stall, Bram walks the plots, and Nessa watches the gate. After dusk they walk home: the stall, the potting shed, and a placed home kit or the gate. |
| L2 | Rest of the garden | Schedule and economy, coarse movement | Resident needs tick in data. Bodies farther than the software cap are not spawned. |
| L3 | Off-screen district | Home, job, relationship summary | A jelly outside the camera hides. A resident walks to the nearest placed home kit; a visitor keeps the flower. Back in frame, the body shows again. The directory still lists each resident's home and job. |
| L4 | Aggregate population | Demand, employment, venue use | The parish page lists every venue. Petal Stall demand is the people present plus creature residents. Demand for every other room is not simulated. |

The software renderer caps non-resident jellies at 4 (8 otherwise). Residents are exempt so Cara stays present. That cap is a stand-in for L2, not a finished LOD system.

When a jelly becomes relevant again, `grove_view` builds an actor from the species record and places it on a walkable plot. The sim does not depend on the actor existing.

Phase A is the garden. Districts, venues beyond the Petal Stall, and the agent trust ladder are data so later phases can reuse them. They are not a city.
