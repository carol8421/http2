{-# LANGUAGE NamedFieldPuns #-}

module Network.HTTP2.Arch.Context where

import Control.Concurrent.STM
import Data.IORef

import Imports
import Network.HPACK
import Network.HTTP2.Arch.Stream
import Network.HTTP2.Arch.Types
import Network.HTTP2.Frame
import Network.HTTP2.Priority

data Role = Client | Server deriving (Eq,Show)

----------------------------------------------------------------

-- | The context for HTTP/2 connection.
data Context = Context {
    role               :: Role
  -- HTTP/2 settings received from a browser
  , http2settings      :: IORef Settings
  , firstSettings      :: IORef Bool
  , streamTable        :: StreamTable
  , concurrency        :: IORef Int
  , priorityTreeSize   :: IORef Int
  -- | RFC 7540 says "Other frames (from any stream) MUST NOT
  --   occur between the HEADERS frame and any CONTINUATION
  --   frames that might follow". This field is used to implement
  --   this requirement.
  , continued          :: IORef (Maybe StreamId)
  , myStreamId         :: IORef StreamId
  , peerStreamId       :: IORef StreamId
  , inputQ             :: TQueue Input -- Server only
  , outputQ            :: PriorityTree Output
  , controlQ           :: TQueue Control
  , encodeDynamicTable :: DynamicTable
  , decodeDynamicTable :: DynamicTable
  -- the connection window for data from a server to a browser.
  , connectionWindow   :: TVar WindowSize
  }

----------------------------------------------------------------

newContext :: Role -> IO Context
newContext rl =
    Context rl <$> newIORef defaultSettings
               <*> newIORef False
               <*> newStreamTable
               <*> newIORef 0
               <*> newIORef 0
               <*> newIORef Nothing
               <*> newIORef sid0
               <*> newIORef 0
               <*> newTQueueIO
               <*> newPriorityTree
               <*> newTQueueIO
               <*> newDynamicTableForEncoding defaultDynamicTableSize
               <*> newDynamicTableForDecoding defaultDynamicTableSize 4096
               <*> newTVarIO defaultInitialWindowSize
   where
     sid0 | rl == Client = 1
          | otherwise    = 2

clearContext :: Context -> IO ()
clearContext _ctx = return ()

----------------------------------------------------------------

isClient :: Context -> Bool
isClient ctx = role ctx == Client

isServer :: Context -> Bool
isServer ctx = role ctx == Server

----------------------------------------------------------------

getMyNewStreamId :: Context -> IO StreamId
getMyNewStreamId ctx = atomicModifyIORef' (myStreamId ctx) inc2
  where
    inc2 n = let n' = n + 2 in (n', n)

getPeerStreamID :: Context -> IO StreamId
getPeerStreamID ctx = readIORef $ peerStreamId ctx

setPeerStreamID :: Context -> StreamId -> IO ()
setPeerStreamID ctx sid =  writeIORef (peerStreamId ctx) sid

----------------------------------------------------------------

{-# INLINE setStreamState #-}
setStreamState :: Context -> Stream -> StreamState -> IO ()
setStreamState _ Stream{streamState} val = writeIORef streamState val

opened :: Context -> Stream -> IO ()
opened ctx@Context{concurrency} strm = do
    atomicModifyIORef' concurrency (\x -> (x+1,()))
    setStreamState ctx strm (Open JustOpened)

halfClosedRemote :: Context -> Stream -> IO ()
halfClosedRemote ctx stream@Stream{streamState} = do
    closingCode <- atomicModifyIORef streamState closeHalf
    traverse_ (closed ctx stream) closingCode
  where
    closeHalf :: StreamState -> (StreamState, Maybe ClosedCode)
    closeHalf x@(Closed _)         = (x, Nothing)
    closeHalf (HalfClosedLocal cc) = (Closed cc, Just cc)
    closeHalf _                    = (HalfClosedRemote, Nothing)

halfClosedLocal :: Context -> Stream -> ClosedCode -> IO ()
halfClosedLocal ctx stream@Stream{streamState} cc = do
    shouldFinalize <- atomicModifyIORef streamState closeHalf
    when shouldFinalize $
        closed ctx stream cc
  where
    closeHalf :: StreamState -> (StreamState, Bool)
    closeHalf x@(Closed _)     = (x, False)
    closeHalf HalfClosedRemote = (Closed cc, True)
    closeHalf _                = (HalfClosedLocal cc, False)

closed :: Context -> Stream -> ClosedCode -> IO ()
closed ctx@Context{concurrency,streamTable} strm@Stream{streamNumber} cc = do
    remove streamTable streamNumber
    -- TODO: prevent double-counting
    atomicModifyIORef' concurrency (\x -> (x-1,()))
    setStreamState ctx strm (Closed cc) -- anyway
