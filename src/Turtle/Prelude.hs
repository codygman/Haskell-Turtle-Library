{-# LANGUAGE CPP                        #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE RankNTypes                 #-}

-- | This module provides a large suite of utilities that resemble Unix
--  utilities.
--
--  Many of these commands are just existing Haskell commands renamed to match
--  their Unix counterparts:
--
-- >>> :set -XOverloadedStrings
-- >>> cd "/tmp"
-- >>> pwd
-- FilePath "/tmp"
--
-- Some commands are `Shell`s that emit streams of values.  `view` prints all
-- values in a `Shell` stream:
--
-- >>> view (ls "/usr")
-- FilePath "/usr/lib"
-- FilePath "/usr/src"
-- FilePath "/usr/sbin"
-- FilePath "/usr/include"
-- FilePath "/usr/share"
-- FilePath "/usr/games"
-- FilePath "/usr/local"
-- FilePath "/usr/bin"
-- >>> view (find (suffix "Browser.py") "/usr/lib")
-- FilePath "/usr/lib/python3.4/idlelib/ClassBrowser.py"
-- FilePath "/usr/lib/python3.4/idlelib/RemoteObjectBrowser.py"
-- FilePath "/usr/lib/python3.4/idlelib/PathBrowser.py"
-- FilePath "/usr/lib/python3.4/idlelib/ObjectBrowser.py"
--
-- Use `fold` to reduce the output of a `Shell` stream:
--
-- >>> import qualified Control.Foldl as Fold
-- >>> fold (ls "/usr") Fold.length
-- 8
-- >>> fold (find (suffix "Browser.py") "/usr/lib") Fold.head
-- Just (FilePath "/usr/lib/python3.4/idlelib/ClassBrowser.py")
--
-- Create files using `output`:
--
-- >>> output "foo.txt" ("123" <|> "456" <|> "ABC")
-- >>> realpath "foo.txt"
-- FilePath "/tmp/foo.txt"
--
-- Read in files using `input`:
--
-- >>> stdout (input "foo.txt")
-- 123
-- 456
-- ABC
--
-- Format strings in a type safe way using `format`:
--
-- >>> dir <- pwd
-- >>> format ("I am in the "%fp%" directory") dir
-- "I am in the /tmp directory"
--
-- Commands like `grep`, `sed` and `find` accept arbitrary `Pattern`s
--
-- >>> stdout (grep ("123" <|> "ABC") (input "foo.txt"))
-- 123
-- ABC
-- >>> let exclaim = fmap (<> "!") (plus digit)
-- >>> stdout (sed exclaim (input "foo.txt"))
-- 123!
-- 456!
-- ABC
--
-- Note that `grep` and `find` differ from their Unix counterparts by requiring
-- that the `Pattern` matches the entire line or file name by default.  However,
-- you can optionally match the prefix, suffix, or interior of a line:
--
-- >>> stdout (grep (has    "2") (input "foo.txt"))
-- 123
-- >>> stdout (grep (prefix "1") (input "foo.txt"))
-- 123
-- >>> stdout (grep (suffix "3") (input "foo.txt"))
-- 123
--
--  You can also build up more sophisticated `Shell` programs using `sh` in
--  conjunction with @do@ notation:
--
-- >{-# LANGUAGE OverloadedStrings #-}
-- >
-- >import Turtle
-- >
-- >main = sh example
-- >
-- >example = do
-- >    -- Read in file names from "files1.txt" and "files2.txt"
-- >    file <- fmap fromText (input "files1.txt" <|> input "files2.txt")
-- >
-- >    -- Stream each file to standard output only if the file exists
-- >    True <- liftIO (testfile file)
-- >    line <- input file
-- >    liftIO (echo line)
--
-- See "Turtle.Tutorial" for an extended tutorial explaining how to use this
-- library in greater detail.

module Turtle.Prelude (
    -- * IO
      echo
    , err
    , readline
    , Filesystem.readTextFile
    , Filesystem.writeTextFile
    , arguments
#if __GLASGOW_HASKELL__ >= 710
    , export
    , unset
#endif
    , need
    , env
    , cd
    , pwd
    , home
    , realpath
    , mv
    , mkdir
    , mktree
    , cp
    , cptree
    , rm
    , rmdir
    , rmtree
    , testfile
    , testdir
    , testpath
    , date
    , datefile
    , touch
    , time
    , hostname
    , which
    , whichAll
    , sleep
    , exit
    , die
    , (.&&.)
    , (.||.)

    -- * Managed
    , readonly
    , writeonly
    , appendonly
    , mktemp
    , mktempfile
    , mktempdir
    , fork
    , wait
    , pushd

    -- * Shell
    , stdin
    , input
    , inhandle
    , stdout
    , output
    , outhandle
    , append
    , stderr
    , strict
    , ls
    , lsif
    , lstree
    , cat
    , grep
    , sed
    , sedPrefix
    , sedSuffix
    , sedEntire
    , onFiles
    , inplace
    , inplacePrefix
    , inplaceSuffix
    , inplaceEntire
    , find
    , yes
    , nl
    , paste
    , endless
    , limit
    , limitWhile
    , cache
    , parallel
    , single

    -- * Folds
    , countChars
    , countWords
    , countLines

    -- * Text
    , cut

    -- * Subprocess management
    , proc
    , shell
    , procs
    , shells
    , inproc
    , inshell
    , sshInshell
    , inprocWithErr
    , inshellWithErr
    , procStrict
    , shellStrict
    , procStrictWithErr
    , shellStrictWithErr

    , system
    , stream
    , streamWithErr
    , systemStrict
    , systemStrictWithErr

    -- * Permissions
    , Permissions(..)
    , chmod
    , getmod
    , setmod
    , copymod
    , readable, nonreadable
    , writable, nonwritable
    , executable, nonexecutable
    , ooo,roo,owo,oox,rwo,rox,owx,rwx

    -- * File size
    , du
    , Size
    , sz
    , bytes
    , kilobytes
    , megabytes
    , gigabytes
    , terabytes
    , kibibytes
    , mebibytes
    , gibibytes
    , tebibytes

    -- * File status
    , PosixCompat.FileStatus
    , stat
    , lstat
    , fileSize
    , accessTime
    , modificationTime
    , statusChangeTime
    , PosixCompat.isBlockDevice
    , PosixCompat.isCharacterDevice
    , PosixCompat.isNamedPipe
    , PosixCompat.isRegularFile
    , PosixCompat.isDirectory
    , PosixCompat.isSymbolicLink
    , PosixCompat.isSocket

    -- * Headers
    , WithHeader(..)
    , header

    -- * Exceptions
    , ProcFailed(..)
    , ShellFailed(..)
    ) where

import Control.Applicative
import Control.Concurrent (threadDelay)
import Control.Concurrent.Async
    (Async, withAsync, waitSTM, concurrently,
     Concurrently(..))
import qualified Control.Concurrent.Async
import Control.Concurrent.MVar (newMVar, modifyMVar_)
import qualified Control.Concurrent.STM as STM
import qualified Control.Concurrent.STM.TQueue as TQueue
import Control.Exception (Exception, bracket, bracket_, finally, mask, throwIO)
import Control.Foldl (Fold, FoldM(..), genericLength, handles, list, premap)
import qualified Control.Foldl
import qualified Control.Foldl.Text
import Control.Monad (guard, liftM, msum, when, unless, (>=>))
import Control.Monad.IO.Class (MonadIO(..))
import Control.Monad.Managed (MonadManaged(..), managed, managed_, runManaged)
#ifdef mingw32_HOST_OS
import Data.Bits ((.&.))
#endif
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Monoid ((<>))
import Data.Text (Text, pack, unpack)
import Data.Time (NominalDiffTime, UTCTime, getCurrentTime)
import Data.Time.Clock.POSIX (POSIXTime)
import Data.Traversable
import qualified Data.Text    as Text
import qualified Data.Text.IO as Text
import Data.Typeable (Typeable)
import qualified Filesystem
import Filesystem.Path.CurrentOS (FilePath, (</>))
import qualified Filesystem.Path.CurrentOS as Filesystem
import GHC.IO.Exception (IOErrorType(UnsupportedOperation))
import Network.HostName (getHostName)
import System.Clock (Clock(..), TimeSpec(..), getTime)
import System.Environment (
    getArgs,
#if __GLASGOW_HASKELL__ >= 710
    setEnv,
    unsetEnv,
#endif
#if __GLASGOW_HASKELL__ >= 708
    lookupEnv,
#endif
    getEnvironment )
import qualified System.Directory
import qualified System.Directory as Directory
import System.Exit (ExitCode(..), exitWith)
import System.IO (Handle, hClose)
import qualified System.IO as IO
import System.IO.Temp (withTempDirectory, withTempFile)
import System.IO.Error
    (catchIOError, ioeGetErrorType, isPermissionError, isDoesNotExistError)
import qualified System.PosixCompat as PosixCompat
import qualified System.Process as Process
#ifdef mingw32_HOST_OS
import qualified System.Win32 as Win32
#else
import System.Posix (
    openDirStream,
    readDirStream,
    closeDirStream,
    touchFile )
#endif
import Prelude hiding (FilePath)

import Turtle.Pattern (Pattern, anyChar, chars, match, selfless, sepBy)
import Turtle.Shell
import Turtle.Format (Format, format, makeFormat, d, w, (%))
import Turtle.Internal (ignoreSIGPIPE)
import Turtle.Line

{-| Run a command using @execvp@, retrieving the exit code

    The command inherits @stdout@ and @stderr@ for the current process
-}
proc
    :: MonadIO io
    => Text
    -- ^ Command
    -> [Text]
    -- ^ Arguments
    -> Shell Line
    -- ^ Lines of standard input
    -> io ExitCode
    -- ^ Exit code
proc cmd args =
    system
        ( (Process.proc (unpack cmd) (map unpack args))
            { Process.std_in  = Process.CreatePipe
            , Process.std_out = Process.Inherit
            , Process.std_err = Process.Inherit
            } )

{-| Run a command line using the shell, retrieving the exit code

    This command is more powerful than `proc`, but highly vulnerable to code
    injection if you template the command line with untrusted input

    The command inherits @stdout@ and @stderr@ for the current process
-}
shell
    :: MonadIO io
    => Text
    -- ^ Command line
    -> Shell Line
    -- ^ Lines of standard input
    -> io ExitCode
    -- ^ Exit code
shell cmdLine =
    system
        ( (Process.shell (unpack cmdLine))
            { Process.std_in  = Process.CreatePipe
            , Process.std_out = Process.Inherit
            , Process.std_err = Process.Inherit
            } )

data ProcFailed = ProcFailed
    { procCommand   :: Text
    , procArguments :: [Text]
    , procExitCode  :: ExitCode
    } deriving (Show, Typeable)

instance Exception ProcFailed

{-| This function is identical to `proc` except this throws `ProcFailed` for
    non-zero exit codes
-}
procs
    :: MonadIO io
    => Text
    -- ^ Command
    -> [Text]
    -- ^ Arguments
    -> Shell Line
    -- ^ Lines of standard input
    -> io ()
procs cmd args s = do
    exitCode <- proc cmd args s
    case exitCode of
        ExitSuccess -> return ()
        _           -> liftIO (throwIO (ProcFailed cmd args exitCode))

data ShellFailed = ShellFailed
    { shellCommandLine :: Text
    , shellExitCode    :: ExitCode
    } deriving (Show, Typeable)

instance Exception ShellFailed

{-| This function is identical to `shell` except this throws `ShellFailed` for
    non-zero exit codes
-}
shells
    :: MonadIO io
    => Text
    -- ^ Command line
    -> Shell Line
    -- ^ Lines of standard input
    -> io ()
    -- ^ Exit code
shells cmdline s = do
    exitCode <- shell cmdline s
    case exitCode of
        ExitSuccess -> return ()
        _           -> liftIO (throwIO (ShellFailed cmdline exitCode))

{-| Run a command using @execvp@, retrieving the exit code and stdout as a
    non-lazy blob of Text

    The command inherits @stderr@ for the current process
-}
procStrict
    :: MonadIO io
    => Text
    -- ^ Command
    -> [Text]
    -- ^ Arguments
    -> Shell Line
    -- ^ Lines of standard input
    -> io (ExitCode, Text)
    -- ^ Exit code and stdout
procStrict cmd args =
    systemStrict (Process.proc (Text.unpack cmd) (map Text.unpack args))

{-| Run a command line using the shell, retrieving the exit code and stdout as a
    non-lazy blob of Text

    This command is more powerful than `proc`, but highly vulnerable to code
    injection if you template the command line with untrusted input

    The command inherits @stderr@ for the current process
-}
shellStrict
    :: MonadIO io
    => Text
    -- ^ Command line
    -> Shell Line
    -- ^ Lines of standard input
    -> io (ExitCode, Text)
    -- ^ Exit code and stdout
shellStrict cmdLine = systemStrict (Process.shell (Text.unpack cmdLine))

{-| Run a command using @execvp@, retrieving the exit code, stdout, and stderr
    as a non-lazy blob of Text
-}
procStrictWithErr
    :: MonadIO io
    => Text
    -- ^ Command
    -> [Text]
    -- ^ Arguments
    -> Shell Line
    -- ^ Lines of standard input
    -> io (ExitCode, Text, Text)
    -- ^ (Exit code, stdout, stderr)
procStrictWithErr cmd args =
    systemStrictWithErr (Process.proc (Text.unpack cmd) (map Text.unpack args))

{-| Run a command line using the shell, retrieving the exit code, stdout, and
    stderr as a non-lazy blob of Text

    This command is more powerful than `proc`, but highly vulnerable to code
    injection if you template the command line with untrusted input
-}
shellStrictWithErr
    :: MonadIO io
    => Text
    -- ^ Command line
    -> Shell Line
    -- ^ Lines of standard input
    -> io (ExitCode, Text, Text)
    -- ^ (Exit code, stdout, stderr)
shellStrictWithErr cmdLine =
    systemStrictWithErr (Process.shell (Text.unpack cmdLine))

-- | Halt an `Async` thread, re-raising any exceptions it might have thrown
halt :: Async a -> IO ()
halt a = do
    m <- Control.Concurrent.Async.poll a
    case m of
        Nothing        -> Control.Concurrent.Async.cancel a
        Just (Left  e) -> throwIO e
        Just (Right _) -> return ()

{-| `system` generalizes `shell` and `proc` by allowing you to supply your own
    custom `CreateProcess`.  This is for advanced users who feel comfortable
    using the lower-level @process@ API
-}
system
    :: MonadIO io
    => Process.CreateProcess
    -- ^ Command
    -> Shell Line
    -- ^ Lines of standard input
    -> io ExitCode
    -- ^ Exit code
system p s = liftIO (do
    let open = do
            (m, Nothing, Nothing, ph) <- Process.createProcess p
            case m of
                Just hIn -> IO.hSetBuffering hIn IO.LineBuffering
                _        -> return ()
            return (m, ph)

    -- Prevent double close
    mvar <- newMVar False
    let close handle = do
            modifyMVar_ mvar (\finalized -> do
                unless finalized (ignoreSIGPIPE (hClose handle))
                return True )
    let close' (Just hIn, ph) = do
            close hIn
            Process.terminateProcess ph
        close' (Nothing , ph) = do
            Process.terminateProcess ph

    let handle (Just hIn, ph) = do
            let feedIn :: (forall a. IO a -> IO a) -> IO ()
                feedIn restore =
                    restore (ignoreSIGPIPE (outhandle hIn s)) `finally` close hIn
            mask (\restore ->
                withAsync (feedIn restore) (\a ->
                    restore (Process.waitForProcess ph) `finally` halt a) )
        handle (Nothing , ph) = do
            Process.waitForProcess ph

    bracket open close' handle )


{-| `systemStrict` generalizes `shellStrict` and `procStrict` by allowing you to
    supply your own custom `CreateProcess`.  This is for advanced users who feel
    comfortable using the lower-level @process@ API
-}
systemStrict
    :: MonadIO io
    => Process.CreateProcess
    -- ^ Command
    -> Shell Line
    -- ^ Lines of standard input
    -> io (ExitCode, Text)
    -- ^ Exit code and stdout
systemStrict p s = liftIO (do
    let p' = p
            { Process.std_in  = Process.CreatePipe
            , Process.std_out = Process.CreatePipe
            , Process.std_err = Process.Inherit
            }

    let open = do
            (Just hIn, Just hOut, Nothing, ph) <- liftIO (Process.createProcess p')
            IO.hSetBuffering hIn IO.LineBuffering
            return (hIn, hOut, ph)

    -- Prevent double close
    mvar <- newMVar False
    let close handle = do
            modifyMVar_ mvar (\finalized -> do
                unless finalized (ignoreSIGPIPE (hClose handle))
                return True )

    bracket open (\(hIn, _, ph) -> close hIn >> Process.terminateProcess ph) (\(hIn, hOut, ph) -> do
        let feedIn :: (forall a. IO a -> IO a) -> IO ()
            feedIn restore =
                restore (ignoreSIGPIPE (outhandle hIn s)) `finally` close hIn

        concurrently
            (mask (\restore ->
                withAsync (feedIn restore) (\a ->
                    restore (liftIO (Process.waitForProcess ph)) `finally` halt a ) ))
            (Text.hGetContents hOut) ) )

{-| `systemStrictWithErr` generalizes `shellStrictWithErr` and
    `procStrictWithErr` by allowing you to supply your own custom
    `CreateProcess`.  This is for advanced users who feel comfortable using
    the lower-level @process@ API
-}
systemStrictWithErr
    :: MonadIO io
    => Process.CreateProcess
    -- ^ Command
    -> Shell Line
    -- ^ Lines of standard input
    -> io (ExitCode, Text, Text)
    -- ^ Exit code and stdout
systemStrictWithErr p s = liftIO (do
    let p' = p
            { Process.std_in  = Process.CreatePipe
            , Process.std_out = Process.CreatePipe
            , Process.std_err = Process.CreatePipe
            }

    let open = do
            (Just hIn, Just hOut, Just hErr, ph) <- liftIO (Process.createProcess p')
            IO.hSetBuffering hIn IO.LineBuffering
            return (hIn, hOut, hErr, ph)

    -- Prevent double close
    mvar <- newMVar False
    let close handle = do
            modifyMVar_ mvar (\finalized -> do
                unless finalized (ignoreSIGPIPE (hClose handle))
                return True )

    bracket open (\(hIn, _, _, ph) -> close hIn >> Process.terminateProcess ph) (\(hIn, hOut, hErr, ph) -> do
        let feedIn :: (forall a. IO a -> IO a) -> IO ()
            feedIn restore =
                restore (ignoreSIGPIPE (outhandle hIn s)) `finally` close hIn

        runConcurrently $ (,,)
            <$> Concurrently (mask (\restore ->
                    withAsync (feedIn restore) (\a ->
                        restore (liftIO (Process.waitForProcess ph)) `finally` halt a ) ))
            <*> Concurrently (Text.hGetContents hOut)
            <*> Concurrently (Text.hGetContents hErr) ) )

{-| Run a command using @execvp@, streaming @stdout@ as lines of `Text`

    The command inherits @stderr@ for the current process
-}
inproc
    :: Text
    -- ^ Command
    -> [Text]
    -- ^ Arguments
    -> Shell Line
    -- ^ Lines of standard input
    -> Shell Line
    -- ^ Lines of standard output
inproc cmd args = stream (Process.proc (unpack cmd) (map unpack args))

{-| Run a command line using the shell, streaming @stdout@ as lines of `Text`

    This command is more powerful than `inproc`, but highly vulnerable to code
    injection if you template the command line with untrusted input

    The command inherits @stderr@ for the current process
-}
inshell
    :: Text
    -- ^ Command line
    -> Shell Line
    -- ^ Lines of standard input
    -> Shell Line
    -- ^ Lines of standard output
inshell cmd = stream (Process.shell (unpack cmd))

{-| Run a command line on the specified server using the shell and ssh, streaming @stdout@ as lines of `Text`

    The command inherits @stderr@ for the current process
-}

sshInshell
  :: Text
  -- ^ Server to connect to
  -> Text
  -- ^ command to run
  -> Shell Line
  -- ^ Lines of standard input
  -> Shell Line
  -- ^ Lines of standard output
sshInshell server command = inshell ("ssh " <> server <> " " <> (surroundWithQuotes command))
  where surroundWithQuotes txt = "\"" <> txt <> "\""

waitForProcessThrows :: Process.ProcessHandle -> IO ()
waitForProcessThrows ph = do
    exitCode <- Process.waitForProcess ph
    case exitCode of
        ExitSuccess   -> return ()
        ExitFailure _ -> Control.Exception.throwIO exitCode

{-| `stream` generalizes `inproc` and `inshell` by allowing you to supply your
    own custom `CreateProcess`.  This is for advanced users who feel comfortable
    using the lower-level @process@ API

    Throws an `ExitCode` exception if the command returns a non-zero exit code
-}
stream
    :: Process.CreateProcess
    -- ^ Command
    -> Shell Line
    -- ^ Lines of standard input
    -> Shell Line
    -- ^ Lines of standard output
stream p s = do
    let p' = p
            { Process.std_in  = Process.CreatePipe
            , Process.std_out = Process.CreatePipe
            , Process.std_err = Process.Inherit
            }

    let open = do
            (Just hIn, Just hOut, Nothing, ph) <- liftIO (Process.createProcess p')
            IO.hSetBuffering hIn IO.LineBuffering
            return (hIn, hOut, ph)

    -- Prevent double close
    mvar <- liftIO (newMVar False)
    let close handle = do
            modifyMVar_ mvar (\finalized -> do
                unless finalized (hClose handle)
                return True )

    (hIn, hOut, ph) <- using (managed (bracket open (\(hIn, _, ph) -> close hIn >> Process.terminateProcess ph)))
    let feedIn :: (forall a. IO a -> IO a) -> IO ()
        feedIn restore = restore (outhandle hIn s) `finally` close hIn

    a <- using
        (managed (\k ->
            mask (\restore -> withAsync (feedIn restore) (restore . k))))
    inhandle hOut <|> (liftIO (waitForProcessThrows ph *> halt a) *> empty)

{-| `streamWithErr` generalizes `inprocWithErr` and `inshellWithErr` by allowing
    you to supply your own custom `CreateProcess`.  This is for advanced users
    who feel comfortable using the lower-level @process@ API

    Throws an `ExitCode` exception if the command returns a non-zero exit code
-}
streamWithErr
    :: Process.CreateProcess
    -- ^ Command
    -> Shell Line
    -- ^ Lines of standard input
    -> Shell (Either Line Line)
    -- ^ Lines of standard output
streamWithErr p s = do
    let p' = p
            { Process.std_in  = Process.CreatePipe
            , Process.std_out = Process.CreatePipe
            , Process.std_err = Process.CreatePipe
            }

    let open = do
            (Just hIn, Just hOut, Just hErr, ph) <- liftIO (Process.createProcess p')
            IO.hSetBuffering hIn IO.LineBuffering
            return (hIn, hOut, hErr, ph)

    -- Prevent double close
    mvar <- liftIO (newMVar False)
    let close handle = do
            modifyMVar_ mvar (\finalized -> do
                unless finalized (hClose handle)
                return True )

    (hIn, hOut, hErr, ph) <- using (managed (bracket open (\(hIn, _, _, ph) -> close hIn >> Process.terminateProcess ph)))
    let feedIn :: (forall a. IO a -> IO a) -> IO ()
        feedIn restore = restore (outhandle hIn s) `finally` close hIn

    queue <- liftIO TQueue.newTQueueIO
    let forwardOut :: (forall a. IO a -> IO a) -> IO ()
        forwardOut restore =
            restore (sh (do
                line <- inhandle hOut
                liftIO (STM.atomically (TQueue.writeTQueue queue (Just (Right line)))) ))
            `finally` STM.atomically (TQueue.writeTQueue queue Nothing)
    let forwardErr :: (forall a. IO a -> IO a) -> IO ()
        forwardErr restore =
            restore (sh (do
                line <- inhandle hErr
                liftIO (STM.atomically (TQueue.writeTQueue queue (Just (Left  line)))) ))
            `finally` STM.atomically (TQueue.writeTQueue queue Nothing)
    let drain = Shell (\(FoldM step begin done) -> do
            x0 <- begin
            let loop x numNothing
                    | numNothing < 2 = do
                        m <- STM.atomically (TQueue.readTQueue queue)
                        case m of
                            Nothing -> loop x $! numNothing + 1
                            Just e  -> do
                                x' <- step x e
                                loop x' numNothing
                    | otherwise      = return x
            x1 <- loop x0 (0 :: Int)
            done x1 )

    a <- using
        (managed (\k ->
            mask (\restore -> withAsync (feedIn restore) (restore . k)) ))
    b <- using
        (managed (\k ->
            mask (\restore -> withAsync (forwardOut restore) (restore . k)) ))
    c <- using
        (managed (\k ->
            mask (\restore -> withAsync (forwardErr restore) (restore . k)) ))
    let l `also` r = do
            _ <- l <|> (r *> STM.retry)
            _ <- r
            return ()
    let waitAll = STM.atomically (waitSTM a `also` (waitSTM b `also` waitSTM c))
    drain <|> (liftIO (waitForProcessThrows ph *> waitAll) *> empty)

{-| Run a command using the shell, streaming @stdout@ and @stderr@ as lines of
    `Text`.  Lines from @stdout@ are wrapped in `Right` and lines from @stderr@
    are wrapped in `Left`.

    Throws an `ExitCode` exception if the command returns a non-zero exit code
-}
inprocWithErr
    :: Text
    -- ^ Command
    -> [Text]
    -- ^ Arguments
    -> Shell Line
    -- ^ Lines of standard input
    -> Shell (Either Line Line)
    -- ^ Lines of either standard output (`Right`) or standard error (`Left`)
inprocWithErr cmd args =
    streamWithErr (Process.proc (unpack cmd) (map unpack args))

{-| Run a command line using the shell, streaming @stdout@ and @stderr@ as lines
    of `Text`.  Lines from @stdout@ are wrapped in `Right` and lines from
    @stderr@ are wrapped in `Left`.

    This command is more powerful than `inprocWithErr`, but highly vulnerable to
    code injection if you template the command line with untrusted input

    Throws an `ExitCode` exception if the command returns a non-zero exit code
-}
inshellWithErr
    :: Text
    -- ^ Command line
    -> Shell Line
    -- ^ Lines of standard input
    -> Shell (Either Line Line)
    -- ^ Lines of either standard output (`Right`) or standard error (`Left`)
inshellWithErr cmd = streamWithErr (Process.shell (unpack cmd))

{-| Print exactly one line to @stdout@

    To print more than one line see `Turtle.Format.printf`, which also supports
    formatted output
-}
echo :: MonadIO io => Line -> io ()
echo line = liftIO (Text.putStrLn (lineToText line))

-- | Print exactly one line to @stderr@
err :: MonadIO io => Line -> io ()
err line = liftIO (Text.hPutStrLn IO.stderr (lineToText line))

{-| Read in a line from @stdin@

    Returns `Nothing` if at end of input
-}
readline :: MonadIO io => io (Maybe Line)
readline = liftIO (do
    eof <- IO.isEOF
    if eof
        then return Nothing
        else fmap (Just . unsafeTextToLine . pack) getLine )

-- | Get command line arguments in a list
arguments :: MonadIO io => io [Text]
arguments = liftIO (fmap (map pack) getArgs)

#if __GLASGOW_HASKELL__ >= 710
-- | Set or modify an environment variable
export :: MonadIO io => Text -> Text -> io ()
export key val = liftIO (setEnv (unpack key) (unpack val))

-- | Delete an environment variable
unset :: MonadIO io => Text -> io ()
unset key = liftIO (unsetEnv (unpack key))
#endif

-- | Look up an environment variable
need :: MonadIO io => Text -> io (Maybe Text)
#if __GLASGOW_HASKELL__ >= 708
need key = liftIO (fmap (fmap pack) (lookupEnv (unpack key)))
#else
need key = liftM (lookup key) env
#endif

-- | Retrieve all environment variables
env :: MonadIO io => io [(Text, Text)]
env = liftIO (fmap (fmap toTexts) getEnvironment)
  where
    toTexts (key, val) = (pack key, pack val)

-- | Change the current directory
cd :: MonadIO io => FilePath -> io ()
cd path = liftIO (Filesystem.setWorkingDirectory path)

{-| Change the current directory. Once the current 'Shell' is done, it returns
back to the original directory.

>>> :set -XOverloadedStrings
>>> cd "/"
>>> view (pushd "/tmp" >> pwd)
FilePath "/tmp"
>>> pwd
FilePath "/"
-}
pushd :: MonadManaged managed => FilePath -> managed ()
pushd path = do
    cwd <- pwd
    using (managed_ (bracket_ (cd path) (cd cwd)))

-- | Get the current directory
pwd :: MonadIO io => io FilePath
pwd = liftIO Filesystem.getWorkingDirectory

-- | Get the home directory
home :: MonadIO io => io FilePath
home = liftIO Filesystem.getHomeDirectory

-- | Canonicalize a path
realpath :: MonadIO io => FilePath -> io FilePath
realpath path = liftIO (Filesystem.canonicalizePath path)

#ifdef mingw32_HOST_OS
fILE_ATTRIBUTE_REPARSE_POINT :: Win32.FileAttributeOrFlag
fILE_ATTRIBUTE_REPARSE_POINT = 1024

reparsePoint :: Win32.FileAttributeOrFlag -> Bool
reparsePoint attr = fILE_ATTRIBUTE_REPARSE_POINT .&. attr /= 0
#endif

{-| Stream all immediate children of the given directory, excluding @\".\"@ and
    @\"..\"@
-}
ls :: FilePath -> Shell FilePath
ls path = Shell (\(FoldM step begin done) -> do
    x0 <- begin
    let path' = Filesystem.encodeString path
    canRead <- fmap
         Directory.readable
        (Directory.getPermissions (deslash path'))
#ifdef mingw32_HOST_OS
    reparse <- fmap reparsePoint (Win32.getFileAttributes path')
    if (canRead && not reparse)
        then bracket
            (Win32.findFirstFile (Filesystem.encodeString (path </> "*")))
            (\(h, _) -> Win32.findClose h)
            (\(h, fdat) -> do
                let loop x = do
                        file' <- Win32.getFindDataFileName fdat
                        let file = Filesystem.decodeString file'
                        x' <- if (file' /= "." && file' /= "..")
                            then step x (path </> file)
                            else return x
                        more <- Win32.findNextFile h fdat
                        if more then loop $! x' else done x'
                loop $! x0 )
        else done x0 )
#else
    if canRead
        then bracket (openDirStream path') closeDirStream (\dirp -> do
            let loop x = do
                    file' <- readDirStream dirp
                    case file' of
                        "" -> done x
                        _  -> do
                            let file = Filesystem.decodeString file'
                            x' <- if (file' /= "." && file' /= "..")
                                then step x (path </> file)
                                else return x
                            loop $! x'
            loop $! x0 )
        else done x0 )
#endif

{-| This is used to remove the trailing slash from a path, because
    `getPermissions` will fail if a path ends with a trailing slash
-}
deslash :: String -> String
deslash []     = []
deslash (c0:cs0) = c0:go cs0
  where
    go []     = []
    go ['\\'] = []
    go (c:cs) = c:go cs

-- | Stream all recursive descendents of the given directory
lstree :: FilePath -> Shell FilePath
lstree path = do
    child <- ls path
    isDir <- testdir child
    if isDir
        then return child <|> lstree child
        else return child

{-| Stream all recursive descendents of the given directory

    This skips any directories that fail the supplied predicate

> lstree = lsif (\_ -> return True)
-}
lsif :: (FilePath -> IO Bool) -> FilePath -> Shell FilePath
lsif predicate path = do
    child <- ls path
    isDir <- testdir child
    if isDir
        then do
            continue <- liftIO (predicate child)
            if continue
                then return child <|> lsif predicate child
                else return child
        else return child

{-| Move a file or directory

    Works if the two paths are on the same filesystem.
    If not, @mv@ will still work when dealing with a regular file,
    but the operation will not be atomic
-}
mv :: MonadIO io => FilePath -> FilePath -> io ()
mv oldPath newPath = liftIO $ catchIOError (Filesystem.rename oldPath newPath)
   (\ioe -> if ioeGetErrorType ioe == UnsupportedOperation -- certainly EXDEV
                then do
                    Filesystem.copyFile oldPath newPath
                    Filesystem.removeFile oldPath
                else ioError ioe)

{-| Create a directory

    Fails if the directory is present
-}
mkdir :: MonadIO io => FilePath -> io ()
mkdir path = liftIO (Filesystem.createDirectory False path)

{-| Create a directory tree (equivalent to @mkdir -p@)

    Does not fail if the directory is present
-}
mktree :: MonadIO io => FilePath -> io ()
mktree path = liftIO (Filesystem.createTree path)

-- | Copy a file
cp :: MonadIO io => FilePath -> FilePath -> io ()
cp oldPath newPath = liftIO (Filesystem.copyFile oldPath newPath)

-- | Copy a directory tree
cptree :: MonadIO io => FilePath -> FilePath -> io ()
cptree oldTree newTree = sh (do
    oldPath <- lstree oldTree
    -- The `system-filepath` library treats a path like "/tmp" as a file and not
    -- a directory and fails to strip it as a prefix from `/tmp/foo`.  Adding
    -- `(</> "")` to the end of the path makes clear that the path is a
    -- directory
    Just suffix <- return (Filesystem.stripPrefix (oldTree </> "") oldPath)
    let newPath = newTree </> suffix
    isFile <- testfile oldPath
    if isFile
        then mktree (Filesystem.directory newPath) >> cp oldPath newPath
        else mktree newPath )

-- | Remove a file
rm :: MonadIO io => FilePath -> io ()
rm path = liftIO (Filesystem.removeFile path)

-- | Remove a directory
rmdir :: MonadIO io => FilePath -> io ()
rmdir path = liftIO (Filesystem.removeDirectory path)

{-| Remove a directory tree (equivalent to @rm -r@)

    Use at your own risk
-}
rmtree :: MonadIO io => FilePath -> io ()
rmtree path0 = liftIO (sh (loop path0))
  where
    loop path = do
        linkstat <- lstat path
        let isLink = PosixCompat.isSymbolicLink linkstat
            isDir = PosixCompat.isDirectory linkstat
        if isLink
            then rm path
            else do
                if isDir
                    then (do
                        child <- ls path
                        loop child ) <|> rmdir path
                    else rm path

-- | Check if a file exists
testfile :: MonadIO io => FilePath -> io Bool
testfile path = liftIO (Filesystem.isFile path)

-- | Check if a directory exists
testdir :: MonadIO io => FilePath -> io Bool
testdir path = liftIO (Filesystem.isDirectory path)

-- | Check if a path exists
testpath :: MonadIO io => FilePath -> io Bool
testpath path = do
  exists <- testfile path
  if exists
    then return exists
    else testdir path

{-| Touch a file, updating the access and modification times to the current time

    Creates an empty file if it does not exist
-}
touch :: MonadIO io => FilePath -> io ()
touch file = do
    exists <- testfile file
    liftIO (if exists
#ifdef mingw32_HOST_OS
        then do
            handle <- Win32.createFile
                (Filesystem.encodeString file)
                Win32.gENERIC_WRITE
                Win32.fILE_SHARE_NONE
                Nothing
                Win32.oPEN_EXISTING
                Win32.fILE_ATTRIBUTE_NORMAL
                Nothing
            (creationTime, _, _) <- Win32.getFileTime handle
            systemTime <- Win32.getSystemTimeAsFileTime
            Win32.setFileTime handle creationTime systemTime systemTime
#else
        then touchFile (Filesystem.encodeString file)
#endif
        else output file empty )

{-| This type is the same as @"System.Directory".`System.Directory.Permissions`@
    type except combining the `System.Directory.executable` and
    `System.Directory.searchable` fields into a single `executable` field for
    consistency with the Unix @chmod@.  This simplification is still entirely
    consistent with the behavior of "System.Directory", which treats the two
    fields as interchangeable.
-}
data Permissions = Permissions
    { _readable   :: Bool
    , _writable   :: Bool
    , _executable :: Bool
    } deriving (Eq, Read, Ord, Show)

{-| Under the hood, "System.Directory" does not distinguish between
    `System.Directory.executable` and `System.Directory.searchable`.  They both
    translate to the same `System.Posix.ownerExecuteMode` permission.  That
    means that we can always safely just set the `System.Directory.executable`
    field and safely leave the `System.Directory.searchable` field as `False`
    because the two fields are combined with (`||`) to determine whether to set
    the executable bit.
-}
toSystemDirectoryPermissions :: Permissions -> System.Directory.Permissions
toSystemDirectoryPermissions p =
    ( System.Directory.setOwnerReadable   (_readable   p)
    . System.Directory.setOwnerWritable   (_writable   p)
    . System.Directory.setOwnerExecutable (_executable p)
    ) System.Directory.emptyPermissions

fromSystemDirectoryPermissions :: System.Directory.Permissions -> Permissions
fromSystemDirectoryPermissions p = Permissions
    { _readable   = System.Directory.readable p
    , _writable   = System.Directory.writable p
    , _executable =
        System.Directory.executable p || System.Directory.searchable p
    }

{-| Update a file or directory's user permissions

> chmod rwo         "foo.txt"  -- chmod u=rw foo.txt
> chmod executable  "foo.txt"  -- chmod u+x foo.txt
> chmod nonwritable "foo.txt"  -- chmod u-w foo.txt

    The meaning of each permission is:

    * `readable` (@+r@ for short): For files, determines whether you can read
      from that file (such as with `input`).  For directories, determines
      whether or not you can list the directory contents (such as with `ls`).
      Note: if a directory is not readable then `ls` will stream an empty list
      of contents

    * `writable` (@+w@ for short): For files, determines whether you can write
      to that file (such as with `output`).  For directories, determines whether
      you can create a new file underneath that directory.

    * `executable` (@+x@ for short): For files, determines whether or not that
      file is executable (such as with `proc`).  For directories, determines
      whether or not you can read or execute files underneath that directory
      (such as with `input` or `proc`)
-}
chmod
    :: MonadIO io
    => (Permissions -> Permissions)
    -- ^ Permissions update function
    -> FilePath
    -- ^ Path
    -> io Permissions
    -- ^ Updated permissions
chmod modifyPermissions path = liftIO (do
    let path' = deslash (Filesystem.encodeString path)
    permissions <- Directory.getPermissions path'
    let permissions' = fromSystemDirectoryPermissions permissions
    let permissions'' = modifyPermissions permissions'
        changed = permissions' /= permissions''
    let permissions''' = toSystemDirectoryPermissions permissions'
    when changed (Directory.setPermissions path' permissions''')
    return permissions' )

-- | Get a file or directory's user permissions
getmod :: MonadIO io => FilePath -> io Permissions
getmod path = liftIO (do
    let path' = deslash (Filesystem.encodeString path)
    permissions <- Directory.getPermissions path'
    return (fromSystemDirectoryPermissions permissions))

-- | Set a file or directory's user permissions
setmod :: MonadIO io => Permissions -> FilePath -> io ()
setmod permissions path = liftIO (do
    let path' = deslash (Filesystem.encodeString path)
    Directory.setPermissions path' (toSystemDirectoryPermissions permissions) )

-- | Copy a file or directory's permissions (analogous to @chmod --reference@)
copymod :: MonadIO io => FilePath -> FilePath -> io ()
copymod sourcePath targetPath = liftIO (do
    let sourcePath' = deslash (Filesystem.encodeString sourcePath)
        targetPath' = deslash (Filesystem.encodeString targetPath)
    Directory.copyPermissions sourcePath' targetPath' )

-- | @+r@
readable :: Permissions -> Permissions
readable p = p { _readable = True }

-- | @-r@
nonreadable :: Permissions -> Permissions
nonreadable p = p { _readable = False }

-- | @+w@
writable :: Permissions -> Permissions
writable p = p { _writable = True }

-- | @-w@
nonwritable :: Permissions -> Permissions
nonwritable p = p { _writable = False }

-- | @+x@
executable :: Permissions -> Permissions
executable p = p { _executable = True }

-- | @-x@
nonexecutable :: Permissions -> Permissions
nonexecutable p = p { _executable = False }

-- | @-r -w -x@
ooo :: Permissions -> Permissions
ooo _ = Permissions
    { _readable   = False
    , _writable   = False
    , _executable = False
    }

-- | @+r -w -x@
roo :: Permissions -> Permissions
roo = readable . ooo

-- | @-r +w -x@
owo :: Permissions -> Permissions
owo = writable . ooo

-- | @-r -w +x@
oox :: Permissions -> Permissions
oox = executable . ooo

-- | @+r +w -x@
rwo :: Permissions -> Permissions
rwo = readable . writable . ooo

-- | @+r -w +x@
rox :: Permissions -> Permissions
rox = readable . executable . ooo

-- | @-r +w +x@
owx :: Permissions -> Permissions
owx = writable . executable . ooo

-- | @+r +w +x@
rwx :: Permissions -> Permissions
rwx = readable . writable . executable . ooo

{-| Time how long a command takes in monotonic wall clock time

    Returns the duration alongside the return value
-}
time :: MonadIO io => io a -> io (a, NominalDiffTime)
time io = do
    TimeSpec seconds1 nanoseconds1 <- liftIO (getTime Monotonic)
    a <- io
    TimeSpec seconds2 nanoseconds2 <- liftIO (getTime Monotonic)
    let t = fromIntegral (    seconds2 -     seconds1)
          + fromIntegral (nanoseconds2 - nanoseconds1) / 10^(9::Int)
    return (a, fromRational t)

-- | Get the system's host name
hostname :: MonadIO io => io Text
hostname = liftIO (fmap Text.pack getHostName)

-- | Show the full path of an executable file
which :: MonadIO io => FilePath -> io (Maybe FilePath)
which cmd = fold (whichAll cmd) Control.Foldl.head

-- | Show all matching executables in PATH, not just the first
whichAll :: FilePath -> Shell FilePath
whichAll cmd = do
  Just paths <- need "PATH"
  path <- select (Filesystem.splitSearchPathString . Text.unpack $ paths)
  let path' = path </> cmd

  True <- testfile path'

  let handler :: IOError -> IO Bool
      handler e =
          if isPermissionError e || isDoesNotExistError e
              then return False
              else throwIO e

  let getIsExecutable = fmap _executable (getmod path')
  isExecutable <- liftIO (getIsExecutable `catchIOError` handler)

  guard isExecutable
  return path'

{-| Sleep for the given duration

    A numeric literal argument is interpreted as seconds.  In other words,
    @(sleep 2.0)@ will sleep for two seconds.
-}
sleep :: MonadIO io => NominalDiffTime -> io ()
sleep n = liftIO (threadDelay (truncate (n * 10^(6::Int))))

{-| Exit with the given exit code

    An exit code of @0@ indicates success
-}
exit :: MonadIO io => ExitCode -> io a
exit code = liftIO (exitWith code)

-- | Throw an exception using the provided `Text` message
die :: MonadIO io => Text -> io a
die txt = liftIO (throwIO (userError (unpack txt)))

infixr 2 .||.
infixr 3 .&&.

{-| Analogous to `&&` in Bash

    Runs the second command only if the first one returns `ExitSuccess`
-}
(.&&.) :: Monad m => m ExitCode -> m ExitCode -> m ExitCode
cmd1 .&&. cmd2 = do
    r <- cmd1
    case r of
        ExitSuccess -> cmd2
        _           -> return r

{-| Analogous to `||` in Bash

    Run the second command only if the first one returns `ExitFailure`
-}
(.||.) :: Monad m => m ExitCode -> m ExitCode -> m ExitCode
cmd1 .||. cmd2 = do
    r <- cmd1
    case r of
        ExitFailure _ -> cmd2
        _             -> return r

{-| Create a temporary directory underneath the given directory

    Deletes the temporary directory when done
-}
mktempdir
    :: MonadManaged managed
    => FilePath
    -- ^ Parent directory
    -> Text
    -- ^ Directory name template
    -> managed FilePath
mktempdir parent prefix = using (do
    let parent' = Filesystem.encodeString parent
    let prefix' = unpack prefix
    dir' <- managed (withTempDirectory parent' prefix')
    return (Filesystem.decodeString dir'))

{-| Create a temporary file underneath the given directory

    Deletes the temporary file when done

    Note that this provides the `Handle` of the file in order to avoid a
    potential race condition from the file being moved or deleted before you
    have a chance to open the file.  The `mktempfile` function provides a
    simpler API if you don't need to worry about that possibility.
-}
mktemp
    :: MonadManaged managed
    => FilePath
    -- ^ Parent directory
    -> Text
    -- ^ File name template
    -> managed (FilePath, Handle)
mktemp parent prefix = using (do
    let parent' = Filesystem.encodeString parent
    let prefix' = unpack prefix
    (file', handle) <- managed (\k ->
        withTempFile parent' prefix' (\file' handle -> k (file', handle)) )
    return (Filesystem.decodeString file', handle) )

{-| Create a temporary file underneath the given directory

    Deletes the temporary file when done
-}
mktempfile
    :: MonadManaged managed
    => FilePath
    -- ^ Parent directory
    -> Text
    -- ^ File name template
    -> managed FilePath
mktempfile parent prefix = using (do
    let parent' = Filesystem.encodeString parent
    let prefix' = unpack prefix
    (file', handle) <- managed (\k ->
        withTempFile parent' prefix' (\file' handle -> k (file', handle)) )
    liftIO (hClose handle)
    return (Filesystem.decodeString file') )

-- | Fork a thread, acquiring an `Async` value
fork :: MonadManaged managed => IO a -> managed (Async a)
fork io = using (managed (withAsync io))

-- | Wait for an `Async` action to complete
wait :: MonadIO io => Async a -> io a
wait a = liftIO (Control.Concurrent.Async.wait a)

-- | Read lines of `Text` from standard input
stdin :: Shell Line
stdin = inhandle IO.stdin

-- | Read lines of `Text` from a file
input :: FilePath -> Shell Line
input file = do
    handle <- using (readonly file)
    inhandle handle

-- | Read lines of `Text` from a `Handle`
inhandle :: Handle -> Shell Line
inhandle handle = Shell (\(FoldM step begin done) -> do
    x0 <- begin
    let loop x = do
            eof <- IO.hIsEOF handle
            if eof
                then done x
                else do
                    txt <- Text.hGetLine handle
                    x'  <- step x (unsafeTextToLine txt)
                    loop $! x'
    loop $! x0 )

-- | Stream lines of `Text` to standard output
stdout :: MonadIO io => Shell Line -> io ()
stdout s = sh (do
    line <- s
    liftIO (echo line) )

-- | Stream lines of `Text` to a file
output :: MonadIO io => FilePath -> Shell Line -> io ()
output file s = sh (do
    handle <- using (writeonly file)
    line   <- s
    liftIO (Text.hPutStrLn handle (lineToText line)) )

-- | Stream lines of `Text` to a `Handle`
outhandle :: MonadIO io => Handle -> Shell Line -> io ()
outhandle handle s = sh (do
    line <- s
    liftIO (Text.hPutStrLn handle (lineToText line)) )

-- | Stream lines of `Text` to append to a file
append :: MonadIO io => FilePath -> Shell Line -> io ()
append file s = sh (do
    handle <- using (appendonly file)
    line   <- s
    liftIO (Text.hPutStrLn handle (lineToText line)) )

-- | Stream lines of `Text` to standard error
stderr :: MonadIO io => Shell Line -> io ()
stderr s = sh (do
    line <- s
    liftIO (err line) )

-- | Read in a stream's contents strictly
strict :: MonadIO io => Shell Line -> io Text
strict s = liftM linesToText (fold s list)

-- | Acquire a `Managed` read-only `Handle` from a `FilePath`
readonly :: MonadManaged managed => FilePath -> managed Handle
readonly file = using (managed (Filesystem.withTextFile file IO.ReadMode))

-- | Acquire a `Managed` write-only `Handle` from a `FilePath`
writeonly :: MonadManaged managed => FilePath -> managed Handle
writeonly file = using (managed (Filesystem.withTextFile file IO.WriteMode))

-- | Acquire a `Managed` append-only `Handle` from a `FilePath`
appendonly :: MonadManaged managed => FilePath -> managed Handle
appendonly file = using (managed (Filesystem.withTextFile file IO.AppendMode))

-- | Combine the output of multiple `Shell`s, in order
cat :: [Shell a] -> Shell a
cat = msum

-- | Keep all lines that match the given `Pattern`
grep :: Pattern a -> Shell Line -> Shell Line
grep pattern s = do
    line <- s
    _:_ <- return (match pattern (lineToText line))
    return line

{-| Replace all occurrences of a `Pattern` with its `Text` result

    `sed` performs substitution on a line-by-line basis, meaning that
    substitutions may not span multiple lines.  Additionally, substitutions may
    occur multiple times within the same line, like the behavior of
    @s\/...\/...\/g@.

    Warning: Do not use a `Pattern` that matches the empty string, since it will
    match an infinite number of times.  `sed` tries to detect such `Pattern`s
    and `die` with an error message if they occur, but this detection is
    necessarily incomplete.
-}
sed :: Pattern Text -> Shell Line -> Shell Line
sed pattern s = do
    when (matchesEmpty pattern) (die message)
    let pattern' = fmap Text.concat
            (many (pattern <|> fmap Text.singleton anyChar))
    line   <- s
    txt':_ <- return (match pattern' (lineToText line))
    select (textToLines txt')
  where
    message = "sed: the given pattern matches the empty string"
    matchesEmpty = not . null . flip match ""

{-| Like `sed`, but the provided substitution must match the beginning of the
    line
-}
sedPrefix :: Pattern Text -> Shell Line -> Shell Line
sedPrefix pattern s = do
    line   <- s
    txt':_ <- return (match ((pattern <> chars) <|> chars) (lineToText line))
    select (textToLines txt')

-- | Like `sed`, but the provided substitution must match the end of the line
sedSuffix :: Pattern Text -> Shell Line -> Shell Line
sedSuffix pattern s = do
    line   <- s
    txt':_ <- return (match ((chars <> pattern) <|> chars) (lineToText line))
    select (textToLines txt')

-- | Like `sed`, but the provided substitution must match the entire line
sedEntire :: Pattern Text -> Shell Line -> Shell Line
sedEntire pattern s = do
    line   <- s
    txt':_ <- return (match (pattern <|> chars)(lineToText line))
    select (textToLines txt')

-- | Make a `Shell Text -> Shell Text` function work on `FilePath`s instead.
-- | Ignores any paths which cannot be decoded as valid `Text`.
onFiles :: (Shell Text -> Shell Text) -> Shell FilePath -> Shell FilePath
onFiles f = fmap Filesystem.fromText . f . getRights . fmap Filesystem.toText
  where
    getRights :: forall a. Shell (Either a Text) -> Shell Text
    getRights s = s >>= either (const empty) return


-- | Like `sed`, but operates in place on a `FilePath` (analogous to @sed -i@)
inplace :: MonadIO io => Pattern Text -> FilePath -> io ()
inplace = inplaceWith sed

-- | Like `sedPrefix`, but operates in place on a `FilePath`
inplacePrefix :: MonadIO io => Pattern Text -> FilePath -> io ()
inplacePrefix = inplaceWith sedPrefix

-- | Like `sedSuffix`, but operates in place on a `FilePath`
inplaceSuffix :: MonadIO io => Pattern Text -> FilePath -> io ()
inplaceSuffix = inplaceWith sedSuffix

-- | Like `sedEntire`, but operates in place on a `FilePath`
inplaceEntire :: MonadIO io => Pattern Text -> FilePath -> io ()
inplaceEntire = inplaceWith sedEntire

inplaceWith
    :: MonadIO io
    => (Pattern Text -> Shell Line -> Shell Line)
    -> Pattern Text
    -> FilePath
    -> io ()
inplaceWith sed_ pattern file = liftIO (runManaged (do
    here              <- pwd
    (tmpfile, handle) <- mktemp here "turtle"
    outhandle handle (sed_ pattern (input file))
    liftIO (hClose handle)
    copymod file tmpfile
    mv tmpfile file ))

-- | Search a directory recursively for all files matching the given `Pattern`
find :: Pattern a -> FilePath -> Shell FilePath
find pattern dir = do
    path <- lsif isNotSymlink dir
    Right txt <- return (Filesystem.toText path)
    _:_       <- return (match pattern txt)
    return path
  where
    isNotSymlink :: FilePath -> IO Bool
    isNotSymlink file = do
      file_stat <- lstat file
      return (not (PosixCompat.isSymbolicLink file_stat))

-- | A Stream of @\"y\"@s
yes :: Shell Line
yes = fmap (\_ -> "y") endless

-- | Number each element of a `Shell` (starting at 0)
nl :: Num n => Shell a -> Shell (n, a)
nl s = Shell _foldIO'
  where
    _foldIO' (FoldM step begin done) = _foldIO s (FoldM step' begin' done')
      where
        step' (x, n) a = do
            x' <- step x (n, a)
            let n' = n + 1
            n' `seq` return (x', n')
        begin' = do
            x0 <- begin
            return (x0, 0)
        done' (x, _) = done x

data ZipState a b = Empty | HasA a | HasAB a b | Done

{-| Merge two `Shell`s together, element-wise

    If one `Shell` is longer than the other, the excess elements are
    truncated
-}
paste :: Shell a -> Shell b -> Shell (a, b)
paste sA sB = Shell _foldIOAB
  where
    _foldIOAB (FoldM stepAB beginAB doneAB) = do
        x0 <- beginAB

        tvar <- STM.atomically (STM.newTVar Empty)

        let begin = return ()

        let stepA () a = STM.atomically (do
                x <- STM.readTVar tvar
                case x of
                    Empty -> STM.writeTVar tvar (HasA a)
                    Done  -> return ()
                    _     -> STM.retry )
        let doneA () = STM.atomically (do
                x <- STM.readTVar tvar
                case x of
                    Empty -> STM.writeTVar tvar Done
                    Done  -> return ()
                    _     -> STM.retry )
        let foldA = FoldM stepA begin doneA

        let stepB () b = STM.atomically (do
                x <- STM.readTVar tvar
                case x of
                    HasA a -> STM.writeTVar tvar (HasAB a b)
                    Done   -> return ()
                    _      -> STM.retry )
        let doneB () = STM.atomically (do
                x <- STM.readTVar tvar
                case x of
                    HasA _ -> STM.writeTVar tvar Done
                    Done   -> return ()
                    _      -> STM.retry )
        let foldB = FoldM stepB begin doneB

        withAsync (foldIO sA foldA) (\asyncA -> do
            withAsync (foldIO sB foldB) (\asyncB -> do
                let loop x = do
                        y <- STM.atomically (do
                            z <- STM.readTVar tvar
                            case z of
                                HasAB a b -> do
                                    STM.writeTVar tvar Empty
                                    return (Just (a, b))
                                Done      -> return  Nothing
                                _         -> STM.retry )
                        case y of
                            Nothing -> return x
                            Just ab -> do
                                x' <- stepAB x ab
                                loop $! x'
                x' <- loop $! x0
                wait asyncA
                wait asyncB
                doneAB x' ) )

-- | A `Shell` that endlessly emits @()@
endless :: Shell ()
endless = Shell (\(FoldM step begin _) -> do
    x0 <- begin
    let loop x = do
            x' <- step x ()
            loop $! x'
    loop $! x0 )

-- | Limit a `Shell` to a fixed number of values
limit :: Int -> Shell a -> Shell a
limit n s = Shell (\(FoldM step begin done) -> do
    ref <- newIORef 0  -- I feel so dirty
    let step' x a = do
            n' <- readIORef ref
            writeIORef ref (n' + 1)
            if n' < n then step x a else return x
    foldIO s (FoldM step' begin done) )

{-| Limit a `Shell` to values that satisfy the predicate

    This terminates the stream on the first value that does not satisfy the
    predicate
-}
limitWhile :: (a -> Bool) -> Shell a -> Shell a
limitWhile predicate s = Shell (\(FoldM step begin done) -> do
    ref <- newIORef True
    let step' x a = do
            b <- readIORef ref
            let b' = b && predicate a
            writeIORef ref b'
            if b' then step x a else return x
    foldIO s (FoldM step' begin done) )

{-| Cache a `Shell`'s output so that repeated runs of the script will reuse the
    result of previous runs.  You must supply a `FilePath` where the cached
    result will be stored.

    The stored result is only reused if the `Shell` successfully ran to
    completion without any exceptions.  Note: on some platforms Ctrl-C will
    flush standard input and signal end of file before killing the program,
    which may trick the program into \"successfully\" completing.
-}
cache :: (Read a, Show a) => FilePath -> Shell a -> Shell a
cache file s = do
    let cached = do
            line <- input file
            case reads (Text.unpack (lineToText line)) of
                [(ma, "")] -> return ma
                _          ->
                    die (format ("cache: Invalid data stored in "%w) file)
    exists <- testfile file
    mas    <- fold (if exists then cached else empty) list
    case [ () | Nothing <- mas ] of
        _:_ -> select [ a | Just a <- mas ]
        _   -> do
            handle <- using (writeonly file)
            let justs = do
                    a      <- s
                    liftIO (Text.hPutStrLn handle (Text.pack (show (Just a))))
                    return a
            let nothing = do
                    let n = Nothing :: Maybe ()
                    liftIO (Text.hPutStrLn handle (Text.pack (show n)))
                    empty
            justs <|> nothing

{-| Run a list of IO actions in parallel using fork and wait.


>>> view (parallel [(sleep 3) >> date, date, date])
2016-12-01 17:22:10.83296 UTC
2016-12-01 17:22:07.829876 UTC
2016-12-01 17:22:07.829963 UTC

-}
parallel :: [IO a] -> Shell a
parallel = traverse fork >=> select >=> wait

-- | Split a line into chunks delimited by the given `Pattern`
cut :: Pattern a -> Text -> [Text]
cut pattern txt = head (match (selfless chars `sepBy` pattern) txt)
-- This `head` should be safe ... in theory

-- | Get the current time
date :: MonadIO io => io UTCTime
date = liftIO getCurrentTime

-- | Get the time a file was last modified
datefile :: MonadIO io => FilePath -> io UTCTime
datefile path = liftIO (Filesystem.getModified path)

-- | Get the size of a file or a directory
du :: MonadIO io => FilePath -> io Size
du path = liftIO (do
    isDir <- testdir path
    size <- do
        if isDir
        then do
            let sizes = do
                    child <- lstree path
                    True  <- testfile child
                    liftIO (Filesystem.getSize child)
            fold sizes Control.Foldl.sum
        else Filesystem.getSize path
    return (Size size) )

{-| An abstract file size

    Specify the units you want by using an accessor like `kilobytes`

    The `Num` instance for `Size` interprets numeric literals as bytes
-}
newtype Size = Size { _bytes :: Integer } deriving (Eq, Ord, Num)

instance Show Size where
    show = show . _bytes

{-| `Format` a `Size` using a human readable representation

>>> format sz 42
"42 B"
>>> format sz 2309
"2.309 KB"
>>> format sz 949203
"949.203 KB"
>>> format sz 1600000000
"1.600 GB"
>>> format sz 999999999999999999
"999999.999 TB"
-}
sz :: Format r (Size -> r)
sz = makeFormat (\(Size numBytes) ->
    let (numKilobytes, remainingBytes    ) = numBytes     `quotRem` 1000
        (numMegabytes, remainingKilobytes) = numKilobytes `quotRem` 1000
        (numGigabytes, remainingMegabytes) = numMegabytes `quotRem` 1000
        (numTerabytes, remainingGigabytes) = numGigabytes `quotRem` 1000
    in  if numKilobytes <= 0
        then format (d%" B" ) remainingBytes
        else if numMegabytes == 0
        then format (d%"."%d%" KB") remainingKilobytes remainingBytes
        else if numGigabytes == 0
        then format (d%"."%d%" MB") remainingMegabytes remainingKilobytes
        else if numTerabytes == 0
        then format (d%"."%d%" GB") remainingGigabytes remainingMegabytes
        else format (d%"."%d%" TB") numTerabytes       remainingGigabytes )

-- | Extract a size in bytes
bytes :: Integral n => Size -> n
bytes = fromInteger . _bytes

-- | @1 kilobyte = 1000 bytes@
kilobytes :: Integral n => Size -> n
kilobytes = (`div` 1000) . bytes

-- | @1 megabyte = 1000 kilobytes@
megabytes :: Integral n => Size -> n
megabytes = (`div` 1000) . kilobytes

-- | @1 gigabyte = 1000 megabytes@
gigabytes :: Integral n => Size -> n
gigabytes = (`div` 1000) . megabytes

-- | @1 terabyte = 1000 gigabytes@
terabytes :: Integral n => Size -> n
terabytes = (`div` 1000) . gigabytes

-- | @1 kibibyte = 1024 bytes@
kibibytes :: Integral n => Size -> n
kibibytes = (`div` 1024) . bytes

-- | @1 mebibyte = 1024 kibibytes@
mebibytes :: Integral n => Size -> n
mebibytes = (`div` 1024) . kibibytes

-- | @1 gibibyte = 1024 mebibytes@
gibibytes :: Integral n => Size -> n
gibibytes = (`div` 1024) . mebibytes

-- | @1 tebibyte = 1024 gibibytes@
tebibytes :: Integral n => Size -> n
tebibytes = (`div` 1024) . gibibytes

{-| Count the number of characters in the stream (like @wc -c@)

    This uses the convention that the elements of the stream are implicitly
    ended by newlines that are one character wide
-}
countChars :: Integral n => Fold Line n
countChars =
  premap lineToText Control.Foldl.Text.length +
    charsPerNewline * countLines

charsPerNewline :: Num a => a
#ifdef mingw32_HOST_OS
charsPerNewline = 2
#else
charsPerNewline = 1
#endif

-- | Count the number of words in the stream (like @wc -w@)
countWords :: Integral n => Fold Line n
countWords = premap (Text.words . lineToText) (handles traverse genericLength)

{-| Count the number of lines in the stream (like @wc -l@)

    This uses the convention that each element of the stream represents one
    line
-}
countLines :: Integral n => Fold Line n
countLines = genericLength

-- | Get the status of a file
stat :: MonadIO io => FilePath -> io PosixCompat.FileStatus
stat = liftIO . PosixCompat.getFileStatus . Filesystem.encodeString

-- | Size of the file in bytes. Does not follow symlinks
fileSize :: PosixCompat.FileStatus -> Size
fileSize = fromIntegral . PosixCompat.fileSize

-- | Time of last access
accessTime :: PosixCompat.FileStatus -> POSIXTime
accessTime = realToFrac . PosixCompat.accessTime

-- | Time of last modification
modificationTime :: PosixCompat.FileStatus -> POSIXTime
modificationTime = realToFrac . PosixCompat.modificationTime

-- | Time of last status change (i.e. owner, group, link count, mode, etc.)
statusChangeTime :: PosixCompat.FileStatus -> POSIXTime
statusChangeTime = realToFrac . PosixCompat.statusChangeTime

-- | Get the status of a file, but don't follow symbolic links
lstat :: MonadIO io => FilePath -> io PosixCompat.FileStatus
lstat = liftIO . PosixCompat.getSymbolicLinkStatus . Filesystem.encodeString

data WithHeader a
    = Header a
    -- ^ The first line with the header
    | Row a a
    -- ^ Every other line: 1st element is header, 2nd element is original row
    deriving (Show)

data Pair a b = Pair !a !b

header :: Shell a -> Shell (WithHeader a)
header (Shell k) = Shell k'
  where
    k' (FoldM step begin done) = k (FoldM step' begin' done')
      where
        step' (Pair x Nothing ) a = do
            x' <- step x (Header a)
            return (Pair x' (Just a))
        step' (Pair x (Just a)) b = do
            x' <- step x (Row a b)
            return (Pair x' (Just a))

        begin' = do
            x <- begin
            return (Pair x Nothing)

        done' (Pair x _) = done x

-- | Returns the result of a 'Shell' that outputs a single
-- line:
--
-- > main = do
-- >   Just directory <- single (inshell "pwd" empty)
-- >   print directory
single :: MonadIO io => Shell a -> io a
single s = do
    as <- fold s Control.Foldl.list
    case as of
        [a] -> return a
        _   -> do
            let msg = format ("single: expected 1 line of input but there were "%d%" lines of input") (length as)
            die msg
