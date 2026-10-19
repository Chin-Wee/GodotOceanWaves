---
type: "query"
date: "2026-10-10T04:41:12.157984+00:00"
question: "investigate what it would take to replace fft with gerstner without changing anything else about the simulation"
contributor: "graphify"
outcome: "useful"
source_nodes: ["Wave Simulation", "Fast Fourier Transform", "Wave Cascades"]
---

# Q: investigate what it would take to replace fft with gerstner without changing anything else about the simulation

## Answer

Expanded from graph vocabulary: [wave, waves, simulation, foam]. Current water node publishes per-cascade displacement and normal Texture2DArray maps plus foam states. Keep that contract; replace WaveGenerator spectrum/modulation/Stockham FFT/unpack production with Gerstner map generation that writes displacement, analytical gradients/normals, and Jacobian breaking. Existing foam feedback, water shading, spray, reflections, and interaction foam can then remain in place. Existing wind/fetch/swell/spread/detail controls describe a TMA/JONSWAP spectral field, so map them to a deterministic finite Gerstner component set using current seed/time/cascade settings. Motion and resulting foam/spray will change because a finite wave set cannot reproduce the dense FFT field exactly. map_size remains output-map resolution; benchmark because map generation cost scales with map_size squared times component count.

## Outcome

- Signal: useful

## Source Nodes

- Wave Simulation
- Fast Fourier Transform
- Wave Cascades