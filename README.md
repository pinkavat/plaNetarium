# PlaNetarium

In-development Godot library for N-body orbital dynamics simulation, wherein multiple 'Gravitors' (stars, planets, moons, etc.), moving along fixed Keplerian orbital tracks, generate gravity that acts on 'Gravitees' (satellites, spacecraft, etc.). 

Designed with a focus on game development (real-time performance and easy interactability) rather than actual orbital analysis. May result in spontaneous very-low-altitude intercepts if used as a planning tool.

The Keplerian orbits are computed with W.H. Goodyear's Universal Variable Formulation[^1], while the N-body dynamics ~~are~~ *were* done with Forest and Ruth's fourth-order symplectic integrator[^2], but are now done with PEFRL[^3] (as it's nominally 340x more accurate, at the cost of an extra force sampling).

[^1]:https://ntrs.nasa.gov/citations/19660027556
[^2]:Forest, E.; Ruth, Ronald D. (1990). "Fourth-order symplectic integration". Physica D. 43: 105–117. doi:10.1016/0167-2789(90)90019-L.
[^3]:Omelyan, Igor & Mryglod, Ihor & Reinhard, Folk. (2002). "Optimized Forest-Ruth- and Suzuki-like algorithms for integration of motion in many-body systems". Computer Physics Communications. 146. 188. doi:10.1016/S0010-4655(02)00451-4.

*Skybox starmap from [Solar System Scope](http://solarsystemscope.com/textures), under [CC Attribution 4.0](https://creativecommons.org/licenses/by/4.0/deed.en)*
