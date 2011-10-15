{-# OPTIONS_HADDOCK hide #-}
module Graphics.Gloss.Internals.Interface.Backend.GLUT
  (GLUTState)
where

import Data.IORef                          (IORef)
import Control.Monad                       (when)
import Control.Concurrent                  (threadDelay)
import qualified Graphics.Rendering.OpenGL as GL
import Graphics.UI.GLUT                    (get,($=))
import qualified Graphics.UI.GLUT          as GLUT
import qualified System.Exit               as System

import Graphics.Gloss.Internals.Interface.Backend.Types

data GLUTState = GLUTState

instance Backend GLUTState where
  initBackendState           = glutStateInit
  initializeBackend          = initializeGLUT
  -- non-freeglut doesn't like this: (\_ -> GLUT.leaveMainLoop)
  exitBackend                = (\_ -> System.exitWith System.ExitSuccess)
  openWindow                 = openWindowGLUT
  dumpBackendState           = dumpStateGLUT
  installDisplayCallback     = installDisplayCallbackGLUT
  -- We can ask for this in freeglut, but it doesn't seem to work :(.
  -- (\_ -> GLUT.actionOnWindowClose $= GLUT.MainLoopReturns)
  installWindowCloseCallback = (\_ -> return ())
  installReshapeCallback     = installReshapeCallbackGLUT
  installKeyMouseCallback    = installKeyMouseCallbackGLUT
  installMotionCallback      = installMotionCallbackGLUT
  installIdleCallback        = installIdleCallbackGLUT
  -- Call the GLUT mainloop.
  -- This function will return when something calls GLUT.leaveMainLoop
  runMainLoop                = (\_     -> GLUT.mainLoop)
  postRedisplay              = (\_     -> GLUT.postRedisplay Nothing)
  getWindowDimensions        = (\_     -> get GLUT.windowSize >>= (\(GL.Size sizeX sizeY) -> return (fromEnum sizeX,fromEnum sizeY)))
  elapsedTime                = (\_     -> get GLUT.elapsedTime >>= (\t -> return $ (fromIntegral t) / 1000))
  sleep                      = (\_ sec -> threadDelay (round $ sec * 100000))

glutStateInit :: GLUTState
glutStateInit = GLUTState

initializeGLUT ::
  IORef GLUTState
  -> Bool
  -> IO ()
initializeGLUT _ debug = do
  -- Initialize GLUT
  (_progName, _args)  <- GLUT.getArgsAndInitialize
  glutVersion         <- get GLUT.glutVersion
  when debug
   $ putStr  $ "  glutVersion        = " ++ show glutVersion   ++ "\n"

  GLUT.initialDisplayMode
   $= [ GLUT.RGBMode
      , GLUT.DoubleBuffered]

  -- See if our requested display mode is possible
  displayMode         <- get GLUT.initialDisplayMode
  displayModePossible <- get GLUT.displayModePossible
  when debug
   $ do putStr  $  "  displayMode        = " ++ show displayMode ++ "\n"
                ++ "       possible      = " ++ show displayModePossible ++ "\n"
                ++ "\n"

openWindowGLUT ::
  IORef GLUTState
  -> String
  -> (Int,Int)
  -> (Int,Int) -> IO ()
openWindowGLUT _ windowName (sizeX, sizeY) (posX, posY) = do
  -- Setup and create a new window.
  -- Be sure to set initialWindow{Position,Size} before calling
  -- createWindow. If we don't do this we get wierd half-created
  -- windows some of the time.
  GLUT.initialWindowPosition
   $= GL.Position
      (fromIntegral posX)
      (fromIntegral posY)

  GLUT.initialWindowSize
   $= GL.Size
      (fromIntegral sizeX)
      (fromIntegral sizeY)

  _ <- GLUT.createWindow windowName
  GLUT.windowSize
   $= GL.Size
      (fromIntegral sizeX)
      (fromIntegral sizeY)

  --  Switch some things.
  --  auto repeat interferes with key up / key down checks.
  --  BUGS: this doesn't seem to work?
  GLUT.perWindowKeyRepeat   $= GLUT.PerWindowKeyRepeatOff

dumpStateGLUT ::
  IORef GLUTState
  -> IO ()
dumpStateGLUT _ = do
  wbw             <- get GLUT.windowBorderWidth
  whh             <- get GLUT.windowHeaderHeight
  rgba            <- get GLUT.rgba

  rgbaBD          <- get GLUT.rgbaBufferDepths
  colorBD         <- get GLUT.colorBufferDepth
  depthBD         <- get GLUT.depthBufferDepth
  accumBD         <- get GLUT.accumBufferDepths
  stencilBD       <- get GLUT.stencilBufferDepth

  doubleBuffered  <- get GLUT.doubleBuffered

  colorMask       <- get GLUT.colorMask
  depthMask       <- get GLUT.depthMask

  putStr  $  "* dumpGlutState\n"
    ++ "  windowBorderWidth  = " ++ show wbw            ++ "\n"
    ++ "  windowHeaderHeight = " ++ show whh            ++ "\n"
    ++ "  rgba               = " ++ show rgba           ++ "\n"
    ++ "  depth      rgba    = " ++ show rgbaBD         ++ "\n"
    ++ "             color   = " ++ show colorBD        ++ "\n"
    ++ "             depth   = " ++ show depthBD        ++ "\n"
    ++ "             accum   = " ++ show accumBD        ++ "\n"
    ++ "             stencil = " ++ show stencilBD      ++ "\n"
    ++ "  doubleBuffered     = " ++ show doubleBuffered ++ "\n"
    ++ "  mask         color = " ++ show colorMask      ++ "\n"
    ++ "               depth = " ++ show depthMask      ++ "\n"
    ++ "\n"

installDisplayCallbackGLUT ::
  IORef GLUTState
  -> [Callback]
  -> IO ()
installDisplayCallbackGLUT ref callbacks = GLUT.displayCallback $= callbackDisplay ref callbacks

callbackDisplay ::
  IORef GLUTState
  -> [Callback]
  -> IO ()
callbackDisplay ref callbacks = do
  -- clear the display
  GL.clear [GL.ColorBuffer, GL.DepthBuffer]
  GL.color $ GL.Color4 0 0 0 (1 :: GL.GLfloat)

  -- get the display callbacks from the chain
  let funs  = [f ref | (Display f) <- callbacks]
  sequence_ funs

  -- swap front and back buffers
  GLUT.swapBuffers
  GLUT.reportErrors
  return ()

installReshapeCallbackGLUT ::
  IORef GLUTState
  -> [Callback]
  -> IO ()
installReshapeCallbackGLUT ref callbacks = GLUT.reshapeCallback $= Just (callbackReshape ref callbacks)

callbackReshape ::
  IORef GLUTState
  -> [Callback]
  -> GLUT.Size
  -> IO ()
callbackReshape ref callbacks (GLUT.Size sizeX sizeY)
  = sequence_
  $ map (\f -> f (fromEnum sizeX, fromEnum sizeY))
      [f ref | Reshape f <- callbacks]

installKeyMouseCallbackGLUT ::
  IORef GLUTState
  -> [Callback]
  -> IO ()
installKeyMouseCallbackGLUT ref callbacks = GLUT.keyboardMouseCallback $= Just (callbackKeyMouse ref callbacks)

callbackKeyMouse ::
  IORef GLUTState
  -> [Callback]
  -> GLUT.Key
  -> GLUT.KeyState
  -> GLUT.Modifiers
  -> GLUT.Position
  -> IO ()
callbackKeyMouse ref callbacks key keystate modifiers (GLUT.Position posX posY)
  = sequence_
  $ map (\f -> f key' keyState' modifiers' pos)
      [f ref | KeyMouse f <- callbacks]
  where
    key'       = glutKeyToKey key
    keyState'  = glutKeyStateToKeyState keystate
    modifiers' = glutModifiersToModifiers modifiers
    pos        = (fromEnum posX, fromEnum posY)

installMotionCallbackGLUT ::
  IORef GLUTState
  -> [Callback]
  -> IO ()
installMotionCallbackGLUT ref callbacks = GLUT.motionCallback $= Just (callbackMotion ref callbacks)

callbackMotion ::
  IORef GLUTState
  -> [Callback]
  -> GLUT.Position
  -> IO ()
callbackMotion ref callbacks (GLUT.Position posX posY)
  = sequence_
  $ map (\f -> f pos)
    [f ref | Motion f <- callbacks]
  where
    pos = (fromEnum posX, fromEnum posY)

installIdleCallbackGLUT ::
  IORef GLUTState
  -> [Callback]
  -> IO ()
installIdleCallbackGLUT ref callbacks = GLUT.idleCallback $= Just (callbackIdle ref callbacks)

callbackIdle ::
  IORef GLUTState
  -> [Callback]
  -> IO ()
callbackIdle ref callbacks
  = sequence_
  $ [f ref | Idle f <- callbacks]

glutKeyToKey ::
  GLUT.Key
  -> Key
glutKeyToKey key =
  case key of
    GLUT.Char '\27'                            -> SpecialKey KeyEsc
    GLUT.Char '\32'                            -> SpecialKey KeySpace
    GLUT.Char '\13'                            -> SpecialKey KeyEnter
    GLUT.Char '\9'                             -> SpecialKey KeyTab
    GLUT.Char '\127'                           -> SpecialKey KeyBackspace
    GLUT.Char c                                -> Char c
    GLUT.SpecialKey GLUT.KeyF1                 -> SpecialKey KeyF1
    GLUT.SpecialKey GLUT.KeyF2                 -> SpecialKey KeyF2
    GLUT.SpecialKey GLUT.KeyF3                 -> SpecialKey KeyF3
    GLUT.SpecialKey GLUT.KeyF4                 -> SpecialKey KeyF4
    GLUT.SpecialKey GLUT.KeyF5                 -> SpecialKey KeyF5
    GLUT.SpecialKey GLUT.KeyF6                 -> SpecialKey KeyF6
    GLUT.SpecialKey GLUT.KeyF7                 -> SpecialKey KeyF7
    GLUT.SpecialKey GLUT.KeyF8                 -> SpecialKey KeyF8
    GLUT.SpecialKey GLUT.KeyF9                 -> SpecialKey KeyF9
    GLUT.SpecialKey GLUT.KeyF10                -> SpecialKey KeyF10
    GLUT.SpecialKey GLUT.KeyF11                -> SpecialKey KeyF11
    GLUT.SpecialKey GLUT.KeyF12                -> SpecialKey KeyF12
    GLUT.SpecialKey GLUT.KeyLeft               -> SpecialKey KeyLeft
    GLUT.SpecialKey GLUT.KeyUp                 -> SpecialKey KeyUp
    GLUT.SpecialKey GLUT.KeyRight              -> SpecialKey KeyRight
    GLUT.SpecialKey GLUT.KeyDown               -> SpecialKey KeyDown
    GLUT.SpecialKey GLUT.KeyPageUp             -> SpecialKey KeyPageUp
    GLUT.SpecialKey GLUT.KeyPageDown           -> SpecialKey KeyPageDown
    GLUT.SpecialKey GLUT.KeyHome               -> SpecialKey KeyHome
    GLUT.SpecialKey GLUT.KeyEnd                -> SpecialKey KeyEnd
    GLUT.SpecialKey GLUT.KeyInsert             -> SpecialKey KeyInsert
    GLUT.SpecialKey GLUT.KeyNumLock            -> SpecialKey KeyNumLock
    GLUT.SpecialKey GLUT.KeyBegin              -> SpecialKey KeyBegin
    GLUT.SpecialKey GLUT.KeyDelete             -> SpecialKey KeyDelete
    GLUT.MouseButton GLUT.LeftButton           -> MouseButton LeftButton
    GLUT.MouseButton GLUT.MiddleButton         -> MouseButton MiddleButton
    GLUT.MouseButton GLUT.RightButton          -> MouseButton RightButton
    GLUT.MouseButton GLUT.WheelUp              -> MouseButton WheelUp
    GLUT.MouseButton GLUT.WheelDown            -> MouseButton WheelDown
    GLUT.MouseButton (GLUT.AdditionalButton i) -> MouseButton (AdditionalButton i)

glutKeyStateToKeyState ::
  GLUT.KeyState
  -> KeyState
glutKeyStateToKeyState GLUT.Down = Down
glutKeyStateToKeyState GLUT.Up   = Up

glutModifiersToModifiers ::
  GLUT.Modifiers
  -> Modifiers
glutModifiersToModifiers (GLUT.Modifiers a b c) =
  Modifiers (glutKeyStateToKeyState a) (glutKeyStateToKeyState b) (glutKeyStateToKeyState c)
