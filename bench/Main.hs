{-# LANGUAGE BangPatterns #-}

module Main where

import Control.Concurrent.STM
import Criterion.Main
import Data.List (foldl')
import System.Random

import qualified ArrayOfQueue as A
import qualified ArrayOfQueueIO as AIO
import qualified BinaryHeap as B
import qualified BinaryHeapIO as BIO
import qualified Heap as O
import qualified Network.HTTP2.Priority.PSQ as P
import qualified RandomSkewHeap as R

numOfStreams :: Int
numOfStreams = 100

numOfTrials :: Int
numOfTrials = 10000

main :: IO ()
main = do
    gen <- getStdGen
    let xs = take numOfStreams $ randomRs (1,256) gen
        ks = [1,3..]
        ys = zip ks xs
    defaultMain [
        bgroup "enqueue & dequeue" [
              bench "Random Skew Heap"      $ whnf enqdeqR xs
            , bench "Okasaki Heap"          $ whnf enqdeqO xs
            , bench "Priority Search Queue" $ whnf enqdeqP ys
            , bench "Binary Heap STM"       $ nfIO (enqdeqB xs)
            , bench "Binary Heap IO"        $ nfIO (enqdeqBIO xs)
            , bench "Array of Queue STM"    $ nfIO (enqdeqA xs)
            , bench "Array of Queue IO"     $ nfIO (enqdeqAIO xs)
            ]
      , bgroup "delete" [
              bench "Priority Search Queue" $ whnf deleteP ys
            ]
      ]

----------------------------------------------------------------

enqdeqR :: [Int] -> ()
enqdeqR ys = loop pq numOfTrials
  where
    !pq = createR ys R.empty
    loop _ 0  = ()
    loop q !n = case R.dequeue q of
        Nothing -> error "enqdeqR"
        Just (ent,q') -> let !q'' = R.enqueue ent q'
                         in loop q'' (n - 1)

createR :: [Int] -> R.PriorityQueue Int -> R.PriorityQueue Int
createR [] !q = q
createR (x:xs) !q = createR xs q'
  where
    !ent = R.newEntry x x
    !q' = R.enqueue ent q

----------------------------------------------------------------

enqdeqO :: [Int] -> ()
enqdeqO xs = loop pq numOfTrials
  where
    !pq = createO xs O.empty
    loop _ 0  = ()
    loop q !n = case O.dequeue q of
        Nothing -> error "enqdeqO"
        Just (ent,q') -> let !q'' = O.enqueue ent q'
                         in loop q'' (n - 1)

createO :: [Int] -> O.PriorityQueue Int -> O.PriorityQueue Int
createO [] !q = q
createO (x:xs) !q = createO xs q'
  where
    !ent = O.newEntry x x
    !q' = O.enqueue ent q

----------------------------------------------------------------

enqdeqP :: [(Int,Int)] -> ()
enqdeqP xs = loop pq numOfTrials
  where
    !pq = createP xs P.empty
    loop _ 0  = ()
    loop q !n = case P.dequeue q of
        Nothing -> error "enqdeqP"
        Just (k,ent,q') -> let !q'' = P.enqueue k ent q'
                           in loop q'' (n - 1)

deleteP :: [(Int,Int)] -> P.PriorityQueue Int
deleteP xs = foldl' P.delete pq ks
  where
    !pq = createP xs P.empty
    (ks,_) = unzip xs

createP :: [(Int,Int)] -> P.PriorityQueue Int -> P.PriorityQueue Int
createP [] !q = q
createP ((k,x):xs) !q = createP xs q'
  where
    !ent = P.newEntry x x
    !q' = P.enqueue k ent q

----------------------------------------------------------------

enqdeqB :: [Int] -> IO ()
enqdeqB xs = do
    q <- atomically (B.new numOfStreams)
    createB xs q
    loop q numOfTrials
  where
    loop _ 0  = return ()
    loop q !n = do
        ent <- atomically $ B.dequeue q
        atomically $ B.enqueue ent q
        loop q (n - 1)

createB :: [Int] -> B.PriorityQueue Int -> IO ()
createB [] _      = return ()
createB (x:xs) !q = do
    let !ent = B.newEntry x x
    atomically $ B.enqueue ent q
    createB xs q

----------------------------------------------------------------

enqdeqBIO :: [Int] -> IO ()
enqdeqBIO xs = do
    q <- BIO.new numOfStreams
    createBIO xs q
    loop q numOfTrials
  where
    loop _ 0  = return ()
    loop q !n = do
        ent <- BIO.dequeue q
        BIO.enqueue ent q
        loop q (n - 1)

createBIO :: [Int] -> BIO.PriorityQueue Int -> IO ()
createBIO [] _      = return ()
createBIO (x:xs) !q = do
    let !ent = BIO.newEntry x x
    BIO.enqueue ent q
    createBIO xs q

----------------------------------------------------------------

enqdeqA :: [Int] -> IO ()
enqdeqA xs = do
    q <- atomically A.new
    createA xs q
    loop q numOfTrials
  where
    loop _ 0  = return ()
    loop q !n = do
        ent <- atomically $ A.dequeue q
        atomically $ A.enqueue ent q
        loop q (n - 1)

createA :: [Int] -> A.PriorityQueue Int -> IO ()
createA [] _      = return ()
createA (x:xs) !q = do
    let !ent = A.newEntry x x
    atomically $ A.enqueue ent q
    createA xs q

----------------------------------------------------------------

enqdeqAIO :: [Int] -> IO ()
enqdeqAIO xs = do
    q <- AIO.new
    createAIO xs q
    loop q numOfTrials
  where
    loop _ 0  = return ()
    loop q !n = do
        ent <- AIO.dequeue q
        AIO.enqueue ent q
        loop q (n - 1)

createAIO :: [Int] -> AIO.PriorityQueue Int -> IO ()
createAIO [] _      = return ()
createAIO (x:xs) !q = do
    let !ent = AIO.newEntry x x
    AIO.enqueue ent q
    createAIO xs q

----------------------------------------------------------------
