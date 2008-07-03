{-# LANGUAGE TypeOperators #-}

-- ---------------------------------------------------------------------------
-- |
-- Module      : Data.Array.Vector.Algorithms.Mutable.TriHeap
-- Copyright   : (c) 2008 Dan Doel
-- Maintainer  : Dan Doel <dan.doel@gmail.com>
-- Stability   : Experimental
-- Portability : Non-portable (type operators)
--
-- This module implements operations for working with a trinary heap stored
-- in an unboxed array. Most heapsorts are defined in terms of a binary heap,
-- in which each internal node has at most two children. By contrast, a
-- trinary heap has internal nodes with up to three children. This reduces
-- the number of comparisons in a heapsort slightly, and improves locality
-- (again, slightly) by flattening out the heap.

module Data.Array.Vector.Algorithms.Mutable.TriHeap
       ( -- * Sorting
         sort
       , sortBy
       , sortByBounds
         -- * Heap operations
       , heapify
       , pop
       , popTo
       , sortHeap ) where

import Control.Monad
import Control.Monad.ST

import Data.Array.Vector
import Data.Array.Vector.Algorithms.Common

import qualified Data.Array.Vector.Algorithms.Mutable.Optimal as O

-- | Sorts an entire array using the default ordering.
sort :: (UA e, Ord e) => MUArr e s -> ST s ()
sort = sortBy compare
{-# INLINE sort #-}

-- | Sorts an entire array using a custom ordering.
sortBy :: (UA e) => Comparison e -> MUArr e s -> ST s ()
sortBy cmp a = sortByBounds cmp a 0 (lengthMU a)
{-# INLINE sortBy #-}

-- | Sorts a portion of an array [l,u) using a custom ordering
sortByBounds :: (UA e) => Comparison e -> MUArr e s -> Int -> Int -> ST s ()
sortByBounds cmp a l u
  | len < 2   = return ()
  | len == 2  = O.sort2ByOffset cmp a l
  | len == 3  = O.sort3ByOffset cmp a l
  | len == 4  = O.sort4ByOffset cmp a l
  | otherwise = heapify cmp a l u >> sortHeap cmp a l (l+4) u >> O.sort4ByOffset cmp a l
 where len = u - l
{-# INLINE sortByBounds #-}

-- | Constructs a heap in a portion of an array [l, u)
heapify :: (UA e) => Comparison e -> MUArr e s -> Int -> Int -> ST s ()
heapify cmp a l u = loop $ (len - 1) `div` 3
  where
 len = u - l
 loop k
   | k < 0     = return ()
   | otherwise = readMU a (l+k) >>= \e -> siftByOffset cmp a e l k len >> loop (k - 1)
{-# INLINE heapify #-}

-- | Given a heap stored in a portion of an array [l,u), swaps the
-- top of the heap with the element at u and rebuilds the heap.
pop :: (UA e) => Comparison e -> MUArr e s -> Int -> Int -> ST s ()
pop cmp a l u = popTo cmp a l u u
{-# INLINE pop #-}

-- | Given a heap stored in a portion of an array [l,u) swaps the top
-- of the heap with the element at position t, and rebuilds the heap.
popTo :: (UA e) => Comparison e -> MUArr e s -> Int -> Int -> Int -> ST s ()
popTo cmp a l u t = do al <- readMU a l
                       at <- readMU a t
                       writeMU a t al
                       siftByOffset cmp a at l 0 (u - l)
{-# INLINE popTo #-}

-- | Given a heap stored in a portion of an array [l,u), sorts the
-- highest values into [m,u). The elements in [l,m) are not in any
-- particular order.
sortHeap :: (UA e) => Comparison e -> MUArr e s -> Int -> Int -> Int -> ST s ()
sortHeap cmp a l m u = loop (u-1) >> swap a l m
 where
 loop k
   | m < k     = pop cmp a l k >> loop (k-1)
   | otherwise = return ()
{-# INLINE sortHeap #-}

-- Rebuilds a heap with a hole in it from start downwards. Afterward,
-- the heap property should apply for [start + off, len + off). val
-- is the new value to be put in the hole.
siftByOffset :: (UA e) => Comparison e -> MUArr e s -> e -> Int -> Int -> Int -> ST s ()
siftByOffset cmp a val off start len = sift val start len
 where
 sift val root len
   | child < len = do (child' :*: ac) <- maximumChild cmp a off child len
                      case cmp val ac of
                        LT -> writeMU a (root + off) ac >> sift val child' len
                        _  -> writeMU a (root + off) val
   | otherwise = writeMU a (root + off) val
  where child = root * 3 + 1
{-# INLINE siftByOffset #-}

-- Finds the maximum child of a heap node, given the indx of the first child.
maximumChild :: (UA e) => Comparison e -> MUArr e s -> Int -> Int -> Int -> ST s (Int :*: e)
maximumChild cmp a off child1 len
  | child3 < len = do ac1 <- readMU a (child1 + off)
                      ac2 <- readMU a (child2 + off)
                      ac3 <- readMU a (child3 + off)
                      return $ case cmp ac1 ac2 of
                                 LT -> case cmp ac2 ac3 of
                                         LT -> child3 :*: ac3
                                         _  -> child2 :*: ac2
                                 _  -> case cmp ac1 ac3 of
                                         LT -> child3 :*: ac3
                                         _  -> child1 :*: ac1
  | child2 < len = do ac1 <- readMU a (child1 + off)
                      ac2 <- readMU a (child2 + off)
                      return $ case cmp ac1 ac2 of
                                 LT -> child2 :*: ac2
                                 _  -> child1 :*: ac1
  | otherwise    = do ac1 <- readMU a (child1 + off) ; return (child1 :*: ac1)
 where
 child2 = child1 + 1
 child3 = child1 + 2
{-# INLINE maximumChild #-}