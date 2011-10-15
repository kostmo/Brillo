{-# OPTIONS_HADDOCK hide #-}
{-# LANGUAGE CPP #-}
module Graphics.Gloss.Internals.Interface.Backend.GLFW
  (GLFWState)
where

import Data.IORef                          (IORef,modifyIORef,readIORef,writeIORef)
import Control.Monad                       (unless,when)
import qualified Graphics.Rendering.OpenGL as GL
import Graphics.UI.GLFW                    (WindowValue(..))
import qualified Graphics.UI.GLFW          as GLFW

-- We use GLUT for font rendering. On freeglut-based installations (usually
-- linux) we need to explicitly initialize GLUT before we can use any of it's
-- functions. We also need to deinitialize (exit) GLUT when we close the GLFW
-- window, otherwise opening a gloss window again from GHCi will crash. For
-- the OS X and Windows version of GLUT there are no such restrictions. We
-- assume also assume that only linux installations use freeglut.
#ifdef linux_HOST_OS
import qualified Graphics.UI.GLUT          as GLUT
#endif

import Graphics.Gloss.Internals.Interface.Backend.Types

data GLFWState
  = GLFWState
  { -- | Status of Ctrl, Alt or Shift (Up or Down?)
    modifiers     :: Modifiers
    -- | Latest mouse position
  , mousePosition :: (Int,Int)
    -- | Latest mousewheel position
  , mouseWheelPos :: Int
    -- | Does the screen need to be redrawn?
  , dirtyScreen   :: Bool
    -- | Action that draws on the screen
  , display       :: IO ()
    -- | Action perforrmed when idling
  , idle          :: IO ()
  }

instance Backend GLFWState where
  initBackendState           = glfwStateInit
  initializeBackend          = initializeGLFW
  exitBackend                = exitGLFW
  openWindow                 = openWindowGLFW
  dumpBackendState           = dumpStateGLFW
  installDisplayCallback     = installDisplayCallbackGLFW
  installWindowCloseCallback = installWindowCloseCallbackGLFW
  installReshapeCallback     = installReshapeCallbackGLFW
  installKeyMouseCallback    = installKeyMouseCallbackGLFW
  installMotionCallback      = installMotionCallbackGLFW
  installIdleCallback        = installIdleCallbackGLFW
  runMainLoop                = runMainLoopGLFW
  postRedisplay              = postRedisplayGLFW
  getWindowDimensions        = (\_     -> GLFW.getWindowDimensions)
  elapsedTime                = (\_     -> GLFW.getTime)
  sleep                      = (\_ sec -> GLFW.sleep sec)

glfwStateInit :: GLFWState
glfwStateInit = GLFWState (Modifiers Up Up Up) (0, 0) 0 True (return ()) (return ())

initializeGLFW ::
  IORef GLFWState
  -> Bool
  -> IO ()
initializeGLFW _ debug = do
  _                   <- GLFW.initialize
  glfwVersion         <- GLFW.getGlfwVersion
#ifdef linux_HOST_OS
-- See comment in header on why we initialize GLUT for Linux
  (_progName, _args)  <- GLUT.getArgsAndInitialize
#endif
  when debug
   $ putStr  $ "  glfwVersion        = " ++ show glfwVersion   ++ "\n"

exitGLFW ::
  IORef GLFWState
  -> IO ()
exitGLFW _ = do
#ifdef linux_HOST_OS
-- See comment in header on why we exit GLUT for Linux
  GLUT.exit
#endif
  GLFW.closeWindow

openWindowGLFW ::
  IORef GLFWState
  -> String
  -> (Int,Int)
  -> (Int,Int)
  -> IO ()
openWindowGLFW _ windowName (sizeX,sizeY) (posX,posY) = do
  _ <- GLFW.openWindow
    GLFW.defaultDisplayOptions
      { GLFW.displayOptions_width        = sizeX
      , GLFW.displayOptions_height       = sizeY
      }

  GLFW.setWindowPosition           posX posY
  GLFW.setWindowTitle              windowName
  -- Try to "V-Sync" by setting the number of buffer swaps per vertical refresh to 1
  GLFW.setWindowBufferSwapInterval 1

dumpStateGLFW ::
  IORef a
  -> IO ()
dumpStateGLFW _ = do
  (ww,wh)     <- GLFW.getWindowDimensions
  r           <- GLFW.getWindowValue NumRedBits
  g           <- GLFW.getWindowValue NumGreenBits
  b           <- GLFW.getWindowValue NumBlueBits
  a           <- GLFW.getWindowValue NumAlphaBits
  let rgbaBD  = [r,g,b,a]
  depthBD     <- GLFW.getWindowValue NumDepthBits
  ra          <- GLFW.getWindowValue NumAccumRedBits
  ga          <- GLFW.getWindowValue NumAccumGreenBits
  ba          <- GLFW.getWindowValue NumAccumBlueBits
  aa          <- GLFW.getWindowValue NumAccumAlphaBits
  let accumBD = [ra,ga,ba,aa]
  stencilBD   <- GLFW.getWindowValue NumStencilBits

  auxBuffers  <- GLFW.getWindowValue NumAuxBuffers

  fsaaSamples <- GLFW.getWindowValue NumFsaaSamples

  putStr $ "* dumpGlfwState\n"
    ++ " windowWidth  = " ++ show ww          ++ "\n"
    ++ " windowHeight = " ++ show wh          ++ "\n"
    ++ " depth rgba   = " ++ show rgbaBD      ++ "\n"
    ++ " depth        = " ++ show depthBD     ++ "\n"
    ++ " accum        = " ++ show accumBD     ++ "\n"
    ++ " stencil      = " ++ show stencilBD   ++ "\n"
    ++ " aux Buffers  = " ++ show auxBuffers  ++ "\n"
    ++ " FSAA Samples = " ++ show fsaaSamples ++ "\n"
    ++ "\n"

installDisplayCallbackGLFW ::
  IORef GLFWState
  -> [Callback]
  -> IO ()
installDisplayCallbackGLFW stateRef callbacks = do
  modifyIORef stateRef (\s -> s {display = callbackDisplay stateRef callbacks})

callbackDisplay ::
  IORef GLFWState
  -> [Callback]
  -> IO ()
callbackDisplay stateRef callbacks
 = do
  -- clear the display
  GL.clear [GL.ColorBuffer, GL.DepthBuffer]
  GL.color $ GL.Color4 0 0 0 (1 :: GL.GLfloat)

  -- get the display callbacks from the chain
  let funs  = [f stateRef | (Display f) <- callbacks]
  sequence_ funs

  return ()

installWindowCloseCallbackGLFW ::
  IORef GLFWState
  -> IO ()
installWindowCloseCallbackGLFW _ = GLFW.setWindowCloseCallback $ do
#ifdef linux_HOST_OS
  GLUT.exit
#endif
  return True

installReshapeCallbackGLFW ::
  Backend a
  => IORef a
  -> [Callback]
  -> IO ()
installReshapeCallbackGLFW stateRef callbacks = do
  GLFW.setWindowSizeCallback (callbackReshape stateRef callbacks)

callbackReshape ::
  Backend a
  => IORef a
  -> [Callback]
  -> Int
  -> Int
  -> IO ()
callbackReshape glfwState callbacks sizeX sizeY
  = sequence_
  $ map   (\f -> f (sizeX, sizeY))
    [f glfwState | Reshape f  <- callbacks]

installKeyMouseCallbackGLFW ::
  IORef GLFWState
  -> [Callback]
  -> IO ()
installKeyMouseCallbackGLFW stateRef callbacks = do
  GLFW.setKeyCallback         $ (callbackKeyboard    stateRef callbacks)
  GLFW.setCharCallback        $ (callbackChar        stateRef callbacks)
  GLFW.setMouseButtonCallback $ (callbackMouseButton stateRef callbacks)
  GLFW.setMouseWheelCallback  $ (callbackMouseWheel  stateRef callbacks)

callbackKeyboard ::
  IORef GLFWState
  -> [Callback]
  -> GLFW.Key
  -> Bool
  -> IO ()
callbackKeyboard stateRef callbacks key keystate
 = do
  (modsSet, GLFWState mods pos _ _ _ _) <- setModifiers stateRef key keystate
  unless modsSet $
    sequence_ $
      map (\f -> f key' keystate' mods pos)
      [f stateRef | KeyMouse f <- callbacks]
  where
    key'      = fromGLFW key
    keystate' = if keystate then Down else Up

setModifiers ::
  IORef GLFWState
  -> GLFW.Key
  -> Bool
  -> IO (Bool, GLFWState)
setModifiers stateRef key pressed
 = do
  glfwState <- readIORef stateRef
  let mods  = modifiers glfwState
  let mods' = case key of
        GLFW.KeyLeftShift -> mods {shift = if pressed then Down else Up}
        GLFW.KeyLeftCtrl  -> mods {ctrl  = if pressed then Down else Up}
        GLFW.KeyLeftAlt   -> mods {alt   = if pressed then Down else Up}
        _                 -> mods

  if (mods' /= mods)
    then do
      let glfwState' = glfwState {modifiers = mods'}
      writeIORef stateRef glfwState'
      return (True, glfwState')
    else return (False, glfwState)

callbackChar ::
  IORef GLFWState
  -> [Callback]
  -> Char
  -> Bool
  -> IO ()
callbackChar stateRef callbacks key keystate
 = do
  (GLFWState mods pos _ _ _ _) <- readIORef stateRef
  sequence_ $
    map (\f -> f key' keystate' mods pos) 
    [f stateRef | KeyMouse f <- callbacks]
  where
    key'      = if (fromEnum key == 32) then SpecialKey KeySpace else Char key
    keystate' = if keystate then Down else Up

callbackMouseButton ::
  IORef GLFWState
  -> [Callback]
  -> GLFW.MouseButton
  -> Bool
  -> IO ()
callbackMouseButton stateRef callbacks key keystate
 = do
  (GLFWState mods pos _ _ _ _) <- readIORef stateRef
  sequence_ $
    map (\f -> f key' keystate' mods pos)
    [f stateRef | KeyMouse f <- callbacks]
  where
    key'      = fromGLFW key
    keystate' = if keystate then Down else Up

callbackMouseWheel ::
  IORef GLFWState
  -> [Callback]
  -> Int
  -> IO ()
callbackMouseWheel stateRef callbacks w
 = do
  (key,keystate) <- setMouseWheel stateRef w
  (GLFWState mods pos _ _ _ _) <- readIORef stateRef
  sequence_ $
    map (\f -> f key keystate mods pos)
    [f stateRef | KeyMouse f <- callbacks]

setMouseWheel ::
  IORef GLFWState
  -> Int
  -> IO (Key, KeyState)
setMouseWheel stateRef w
 = do
  glfwState <- readIORef stateRef
  writeIORef stateRef $ glfwState {mouseWheelPos = w}
  case (compare w (mouseWheelPos glfwState)) of
    LT -> return (MouseButton WheelDown , Down)
    GT -> return (MouseButton WheelUp   , Down)
    EQ -> return (SpecialKey  KeyUnknown, Up  )

installMotionCallbackGLFW ::
  IORef GLFWState
  -> [Callback]
  -> IO ()
installMotionCallbackGLFW stateRef callbacks = do
  GLFW.setMousePositionCallback $ (callbackMotion stateRef callbacks)

callbackMotion ::
  IORef GLFWState
  -> [Callback]
  -> Int
  -> Int
  -> IO ()
callbackMotion stateRef callbacks x y
 = do
  pos <- setMousePos stateRef x y
  sequence_ $
    map (\f -> f pos)
    [f stateRef | Motion f <- callbacks]

setMousePos ::
  IORef GLFWState
  -> Int
  -> Int
  -> IO (Int,Int)
setMousePos stateRef x y
 = do
  let pos = (x,y)
  modifyIORef stateRef (\s -> s {mousePosition = pos})
  return pos

installIdleCallbackGLFW ::
  IORef GLFWState
  -> [Callback]
  -> IO ()
installIdleCallbackGLFW stateRef callbacks = do
  modifyIORef stateRef (\s -> s {idle = callbackIdle stateRef callbacks})

callbackIdle ::
  IORef GLFWState
  -> [Callback]
  -> IO ()
callbackIdle stateRef callbacks
  = sequence_
  $ [f stateRef | Idle f <- callbacks]

runMainLoopGLFW ::
  IORef GLFWState
  -> IO ()
runMainLoopGLFW stateRef = do
  windowIsOpen <- GLFW.windowIsOpen
  when windowIsOpen $ do
    d <- fmap dirtyScreen $ readIORef stateRef
    when d $ do
            s <- readIORef stateRef
            display s
            GLFW.swapBuffers
    modifyIORef stateRef $ (\s -> s {dirtyScreen = False})
    (readIORef stateRef) >>= (\s -> idle s)
    GLFW.sleep 0.001
    runMainLoopGLFW stateRef

postRedisplayGLFW ::
  IORef GLFWState
  -> IO ()
postRedisplayGLFW stateRef = modifyIORef stateRef $ (\s -> s {dirtyScreen = True})

class GLFWKey a where
  fromGLFW :: a -> Key

instance GLFWKey GLFW.Key where
  fromGLFW key = case key of
    GLFW.CharKey _      -> SpecialKey KeyUnknown
    GLFW.KeySpace       -> SpecialKey KeySpace
    GLFW.KeyEsc         -> SpecialKey KeyEsc
    GLFW.KeyF1          -> SpecialKey KeyF1
    GLFW.KeyF2          -> SpecialKey KeyF2
    GLFW.KeyF3          -> SpecialKey KeyF3
    GLFW.KeyF4          -> SpecialKey KeyF4
    GLFW.KeyF5          -> SpecialKey KeyF5
    GLFW.KeyF6          -> SpecialKey KeyF6
    GLFW.KeyF7          -> SpecialKey KeyF7
    GLFW.KeyF8          -> SpecialKey KeyF8
    GLFW.KeyF9          -> SpecialKey KeyF9
    GLFW.KeyF10         -> SpecialKey KeyF10
    GLFW.KeyF11         -> SpecialKey KeyF11
    GLFW.KeyF12         -> SpecialKey KeyF12
    GLFW.KeyF13         -> SpecialKey KeyF13
    GLFW.KeyF14         -> SpecialKey KeyF14
    GLFW.KeyF15         -> SpecialKey KeyF15
    GLFW.KeyF16         -> SpecialKey KeyF16
    GLFW.KeyF17         -> SpecialKey KeyF17
    GLFW.KeyF18         -> SpecialKey KeyF18
    GLFW.KeyF19         -> SpecialKey KeyF19
    GLFW.KeyF20         -> SpecialKey KeyF20
    GLFW.KeyF21         -> SpecialKey KeyF21
    GLFW.KeyF22         -> SpecialKey KeyF22
    GLFW.KeyF23         -> SpecialKey KeyF23
    GLFW.KeyF24         -> SpecialKey KeyF24
    GLFW.KeyF25         -> SpecialKey KeyF25
    GLFW.KeyUp          -> SpecialKey KeyUp
    GLFW.KeyDown        -> SpecialKey KeyDown
    GLFW.KeyLeft        -> SpecialKey KeyLeft
    GLFW.KeyRight       -> SpecialKey KeyRight
    GLFW.KeyTab         -> SpecialKey KeyTab
    GLFW.KeyEnter       -> SpecialKey KeyEnter
    GLFW.KeyBackspace   -> SpecialKey KeyBackspace
    GLFW.KeyInsert      -> SpecialKey KeyInsert
    GLFW.KeyDel         -> SpecialKey KeyDelete
    GLFW.KeyPageup      -> SpecialKey KeyPageUp
    GLFW.KeyPagedown    -> SpecialKey KeyPageDown
    GLFW.KeyHome        -> SpecialKey KeyHome
    GLFW.KeyEnd         -> SpecialKey KeyEnd
    GLFW.KeyPad0        -> SpecialKey KeyPad0
    GLFW.KeyPad1        -> SpecialKey KeyPad1
    GLFW.KeyPad2        -> SpecialKey KeyPad2
    GLFW.KeyPad3        -> SpecialKey KeyPad3
    GLFW.KeyPad4        -> SpecialKey KeyPad4
    GLFW.KeyPad5        -> SpecialKey KeyPad5
    GLFW.KeyPad6        -> SpecialKey KeyPad6
    GLFW.KeyPad7        -> SpecialKey KeyPad7
    GLFW.KeyPad8        -> SpecialKey KeyPad8
    GLFW.KeyPad9        -> SpecialKey KeyPad9
    GLFW.KeyPadDivide   -> SpecialKey KeyPadDivide
    GLFW.KeyPadMultiply -> SpecialKey KeyPadMultiply
    GLFW.KeyPadSubtract -> SpecialKey KeyPadSubtract
    GLFW.KeyPadAdd      -> SpecialKey KeyPadAdd
    GLFW.KeyPadDecimal  -> SpecialKey KeyPadDecimal
    GLFW.KeyPadEqual    -> SpecialKey KeyPadEqual
    GLFW.KeyPadEnter    -> SpecialKey KeyPadEnter
    _                   -> SpecialKey KeyUnknown

instance GLFWKey GLFW.MouseButton where
  fromGLFW mouse = case mouse of
    GLFW.MouseButton0 -> MouseButton LeftButton
    GLFW.MouseButton1 -> MouseButton RightButton
    GLFW.MouseButton2 -> MouseButton MiddleButton
    GLFW.MouseButton3 -> MouseButton $ AdditionalButton 3
    GLFW.MouseButton4 -> MouseButton $ AdditionalButton 4
    GLFW.MouseButton5 -> MouseButton $ AdditionalButton 5
    GLFW.MouseButton6 -> MouseButton $ AdditionalButton 6
    GLFW.MouseButton7 -> MouseButton $ AdditionalButton 7
