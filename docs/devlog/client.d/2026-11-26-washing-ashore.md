# Washing ashore (client)

Joining an island server builds the 3 km world on the main thread (about 6 s of node spots,
scatter and flora data). Until that moves onto a thread, `ShoreCover` puts a plain dark screen
with "Washing ashore" over it, so the join reads as arriving, not as a freeze or a crash.
It is drawn once with `RenderingServer.force_draw` before the build (the build holds the main
thread, so a normal frame would never show it) and fades out over 0.6 s after. Worlds of 1 km
or less (Ashgrove) never show it.

Next: thread the data warm-up so the cover is up for a second, not six.
