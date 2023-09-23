# PlaNetarium

In-development Godot library for N-body orbital dynamics simulation, wherein multiple 'Gravitors' (stars, planets, moons, etc.), moving along fixed Keplerian orbital tracks, generate gravity that acts on 'Gravitees' (satellites, spacecraft, etc.). 

Designed with a focus on game development (real-time performance and easy interactability) rather than actual orbital analysis.

The Keplerian orbits are computed with W.H. Goodyear's Universal Variable Formulation[^1], while the N-body dynamics are done with Forest and Ruth's fourth-order symplectic integrator[^2].

[^1]:https://ntrs.nasa.gov/citations/19660027556
[^2]:Forest, E.; Ruth, Ronald D. (1990). "Fourth-order symplectic integration". Physica D. 43: 105–117. doi:10.1016/0167-2789(90)90019-L.
