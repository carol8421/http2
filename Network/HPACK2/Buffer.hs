{-# LANGUAGE BangPatterns, RecordWildCards #-}

module Network.HPACK2.Buffer (
    Buffer
  , BufferSize
  , WorkingBuffer
  , newWorkingBuffer
  , rewind1
  , readW
  , readWord8
  , writeWord8
  , finalPointer
  , toByteString
  , copyByteString
  , ReadBuffer
  , withReadBuffer
  , hasOneByte
  , hasMoreBytes
  , rewindOneByte
  , getByte
  , extractByteString
  ) where

import Foreign.ForeignPtr (withForeignPtr)
import Data.ByteString.Internal (ByteString(..), create, memcpy)
import Data.IORef (IORef, newIORef, readIORef, writeIORef, modifyIORef')
import Data.Word (Word8)
import Foreign.Ptr (plusPtr, minusPtr)
import Foreign.Storable (peek, poke)
import Network.HPACK2.Types (Buffer, BufferSize)

----------------------------------------------------------------

data WorkingBuffer = WorkingBuffer {
    start :: !Buffer
  , limit :: !Buffer
  , offset :: !(IORef Buffer)
  }

newWorkingBuffer :: Buffer -> BufferSize -> IO WorkingBuffer
newWorkingBuffer buf siz = WorkingBuffer buf (buf `plusPtr` siz) <$> newIORef buf

{-# INLINE rewind1 #-}
rewind1 :: WorkingBuffer -> IO ()
rewind1 WorkingBuffer{..} = do
    ptr <- readIORef offset
    let !ptr' = ptr `plusPtr` (-1)
    writeIORef offset ptr'

{-# INLINE readW #-}
readW :: WorkingBuffer -> IO Word8
readW WorkingBuffer{..} = readIORef offset >>= peek

{-# INLINE readWord8 #-}
readWord8 :: WorkingBuffer -> IO (Maybe Word8)
readWord8 WorkingBuffer{..} = do
    ptr <- readIORef offset
    if ptr >= limit then
        return Nothing
      else do
        w <- peek ptr
        return $! Just w

{-# INLINE writeWord8 #-}
writeWord8 :: WorkingBuffer -> Word8 -> IO Bool
writeWord8 WorkingBuffer{..} w = do
    ptr <- readIORef offset
    if ptr >= limit then
        return False
      else do
        poke ptr w
        let ptr' = ptr `plusPtr` 1
        writeIORef offset ptr'
        return True

finalPointer :: WorkingBuffer -> IO Buffer
finalPointer WorkingBuffer{..} = readIORef offset

{-# INLINE copyByteString #-}
copyByteString :: WorkingBuffer -> ByteString -> IO Bool
copyByteString WorkingBuffer{..} (PS fptr off len) = withForeignPtr fptr $ \ptr -> do
    let src = ptr `plusPtr` off
    dst <- readIORef offset
    let !dst' = dst `plusPtr` len
    if dst' >= limit then
        return False
      else do
        memcpy dst src len
        writeIORef offset dst'
        return True

toByteString :: WorkingBuffer -> IO ByteString
toByteString WorkingBuffer{..} = do
    ptr <- readIORef offset
    let !len = ptr `minusPtr` start
    create len $ \p -> memcpy p start len

----------------------------------------------------------------

data ReadBuffer = ReadBuffer {
    beg :: !Buffer
  , end :: !Buffer
  , cur :: !(IORef Buffer)
  }

withReadBuffer :: ByteString -> (ReadBuffer -> IO a) -> IO a
withReadBuffer (PS fp off len) action = withForeignPtr fp $ \ptr -> do
    let !bg = ptr `plusPtr` off
        !ed = bg `plusPtr` len
    nsrc <- ReadBuffer bg ed <$> newIORef bg
    action nsrc

{-# INLINE hasOneByte #-}
hasOneByte :: ReadBuffer -> IO Bool
hasOneByte ReadBuffer{..} = do
    ptr <- readIORef cur
    return $! ptr < end

{-# INLINE hasMoreBytes #-}
hasMoreBytes :: ReadBuffer -> Int -> IO Bool
hasMoreBytes ReadBuffer{..} n = do
    ptr <- readIORef cur
    return $! (end `minusPtr` ptr) >= n

{-# INLINE rewindOneByte #-}
rewindOneByte :: ReadBuffer -> IO ()
rewindOneByte ReadBuffer{..} = modifyIORef' cur (`plusPtr` (-1))

{-# INLINE getByte #-}
getByte :: ReadBuffer -> IO Word8
getByte ReadBuffer{..} = do
    ptr <- readIORef cur
    w <- peek ptr
    writeIORef cur $! ptr `plusPtr` 1
    return w

extractByteString :: ReadBuffer -> Int -> IO ByteString
extractByteString ReadBuffer{..} len = do
    src <- readIORef cur
    bs <- create len $ \dst -> memcpy dst src len
    writeIORef cur $! src `plusPtr` len
    return bs
