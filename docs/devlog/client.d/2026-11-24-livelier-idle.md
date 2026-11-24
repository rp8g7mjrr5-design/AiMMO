# Livelier idle (ws/client/livelier-idle)

**What:** the owner said "I think the problem is how stiff they look". The idle was a near-rest pose with millimetre breathing, so a standing traveller looked like a soldier at attention. `AvatarClips.idle` now stands at ease: the weight on one leg (`idle_weight`, shifting to the other leg every 8 s over about 1.5 s), the hips tilted 0.06 rad over the standing leg with the shoulders tilted against them, soft elbows (0.26 to 0.38 rad), hands turned in, the free foot resting 7 cm forward with a soft knee, and the head turned a little. `client.gd` starts each avatar's animator clock from its appearance seed, so friends standing together never sway in step.

**Tried:** a 3 cm raised free heel read well in stills but fails the "ankles on the ground" check, and the sagittal leg IK can't bend one knee alone, so the free foot steps forward instead.

**Known:** the sculpted-body test camp also gives each archetype its own stance (elder stoops, smith stands wide); that belongs in the idle once looks carry an archetype. Shots: `/mnt/project-files/art-direction/less-stiff/`.
