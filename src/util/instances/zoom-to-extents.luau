-- ONE IMPLEMENTATION, TWO PATHS. This file and `ui/zoom-to-extents` were
-- independent copies of the same function -- same maths, same `INVALID ZOOM!`
-- error, different casing (`zoomToExtents` / `getCameraOffset` here, snake_case
-- there) -- which is how a fix to one of them could be made and still leave the
-- game running the other. `ui/` is the one the code actually reaches for
-- (`ui/templates/viewport` requires it by that path), so that copy is the
-- implementation and this path is kept only so an existing require does not
-- break.
--
-- Prefer `ReplicatedStorage.Util.ui["zoom-to-extents"]` in new code: framing a
-- camera on a model is a viewport concern, not an Instance utility.
const ReplicatedStorage = game:GetService "ReplicatedStorage"

return require(ReplicatedStorage.Util.ui["zoom-to-extents"])
