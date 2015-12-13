module ViperVM.Arch.X86_64.Assembler.LegacyPrefix 
   ( LegacyPrefix(..)
   , RepeatMode(..)
   , Segment(..)
   , toLegacyPrefix
   , putLegacyPrefixes
   , putLegacyPrefix
   , decodeLegacyPrefixes
   ) where

import Data.Word
import Data.Maybe (isJust)
import Data.Foldable (traverse_)
import Control.Monad.State
import Control.Monad.Trans.Either
import qualified Data.Vector.Unboxed as V
import qualified Data.Vector.Unboxed.Mutable as V

import ViperVM.Format.Binary.Put
import ViperVM.Arch.X86_64.Assembler.X86Dec

{-
   Note [Legacy prefixes]
   ~~~~~~~~~~~~~~~~~~~~~~

   There are up to 4 optional legacy prefixes at the beginning of an
   instruction. These prefixes can be in any order. 

   These prefixes are divided up into 4 groups: only a single prefix from each
   group must be used otherwise the behavior is undefined. It seems that some
   processors ignore the subsequent prefixes from the same group or use only
   the last prefix specified for any group.

   Legacy prefixes alter the meaning of the opcode. Originally it was only in
   minor ways (address or operand size, with bus locking, branch hints, etc.).
   Now, these prefixes are used to select totally different sets of
   instructions. In this case the prefix is said to be mandatory (for the
   instruction to be encoded). For example, SSE instructions require a legacy
   prefix.

-}

-- | Identify if the byte is a legacy prefix
isLegacyPrefix :: Word8 -> Bool
isLegacyPrefix = isJust . legacyPrefixGroup


-- | Get the legacy prefix group
legacyPrefixGroup :: Word8 -> Maybe Int
legacyPrefixGroup x = case x of
   -- group 1
   0xF0  -> Just 1
   0xF3  -> Just 1
   0xF2  -> Just 1
   -- group 2
   0x26  -> Just 2
   0x2E  -> Just 2
   0x36  -> Just 2
   0x3E  -> Just 2
   0x64  -> Just 2
   0x65  -> Just 2
   -- group 3
   0x66  -> Just 3
   -- group 4
   0x67  -> Just 4
   _     -> Nothing


data LegacyPrefix
   = PrefixOperandSizeOverride
   | PrefixAddressSizeOverride
   | PrefixSegmentOverride Segment
   | PrefixLock
   | PrefixRepeat RepeatMode
   deriving (Eq, Show)

data RepeatMode
   = RepeatEqual 
   | RepeatNotEqual 
   deriving (Eq,Show)

data Segment
   = CS 
   | DS 
   | ES 
   | FS 
   | GS 
   | SS 
   deriving (Eq,Show)


-- | Write a list of legacy prefixes
putLegacyPrefixes :: [LegacyPrefix] -> Put
putLegacyPrefixes = traverse_ putLegacyPrefix

   
-- | Read a legacy prefix if possible
toLegacyPrefix :: Word8 -> LegacyPrefix
toLegacyPrefix x = case x of
   0x66  -> PrefixOperandSizeOverride
   0x67  -> PrefixAddressSizeOverride
   0x2E  -> PrefixSegmentOverride CS
   0x3E  -> PrefixSegmentOverride DS
   0x26  -> PrefixSegmentOverride ES
   0x64  -> PrefixSegmentOverride FS
   0x65  -> PrefixSegmentOverride GS
   0x36  -> PrefixSegmentOverride SS
   0xF0  -> PrefixLock
   0xF3  -> PrefixRepeat RepeatEqual
   0xF2  -> PrefixRepeat RepeatNotEqual
   _     -> error $ "Invalid prefix value: " ++ show x

-- | Write a legacy prefix
putLegacyPrefix :: LegacyPrefix -> Put
putLegacyPrefix p = putWord8 $ case p of
   PrefixOperandSizeOverride  -> 0x66
   PrefixAddressSizeOverride  -> 0x67
   PrefixSegmentOverride CS   -> 0x2E
   PrefixSegmentOverride DS   -> 0x3E
   PrefixSegmentOverride ES   -> 0x26
   PrefixSegmentOverride FS   -> 0x64
   PrefixSegmentOverride GS   -> 0x65
   PrefixSegmentOverride SS   -> 0x36
   PrefixLock                 -> 0xF0
   PrefixRepeat RepeatEqual   -> 0xF3
   PrefixRepeat RepeatNotEqual-> 0xF2


-- | Decode legacy prefixes. See Note [Legacy prefixes].
--
-- If allowMultiple is set, more than one prefix is allowed per group, but only
-- the last one is taken into account.
--
-- If allowMoreThan4 is set, more than 4 prefixes can be used (it requires
-- allowMultiple)
decodeLegacyPrefixes :: Bool -> Bool -> X86Dec [Word8]
decodeLegacyPrefixes allowMultiple allowMoreThan4 = do
      rec 0 (V.fromList [0,0,0,0])
   where
      rec :: Int -> V.Vector Word8 -> X86Dec [Word8]
      rec n _
         | n > 4 && not allowMoreThan4 = left ErrTooManyLegacyPrefixes

      rec n xs = do
         x <- lookWord8

         case legacyPrefixGroup x of
            Nothing -> return $ V.toList $ V.filter (/= 0) xs

            Just g  -> case xs V.! g of
               y | y /= 0 && not allowMultiple 
                  -> left ErrInvalidLegacyPrefixGroups
               _  -> skipWord8 >> rec (n+1) (V.modify (\v -> V.write v g x) xs)
