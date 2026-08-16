-- Phase 0 pipeline check.
-- If this prints in the Studio Output window on play-test, the chain works:
--   VSCode -> file on disk -> rojo serve -> Studio plugin -> DataModel.

local RunService = game:GetService("RunService")

print("[Bootstrap] Rojo pipeline OK - synced from src/ServerScriptService")
print(("[Bootstrap] Running on %s"):format(RunService:IsStudio() and "Studio" or "live server"))
