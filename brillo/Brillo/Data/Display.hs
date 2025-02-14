module Brillo.Data.Display (Display (..))
where


-- | Describes how Brillo should display its output.
data Display
  = -- | Display in a window with the given name, size and position.
    InWindow String (Int, Int) (Int, Int)
  | -- | Display full screen.
    FullScreen
  deriving (Eq, Read, Show)
