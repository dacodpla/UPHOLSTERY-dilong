-- src/client/init.client.luau
local GrabController = require(script.GrabController)
GrabController.Init()

require(script.MinigameBridge)  -- self-inits via event connection on require
require(script.ConceptHUD)      -- self-inits via event connection on require
