module ViperVM.Arch.X86_64.Assembler.Operand
   ( OperandType(..)
   , Op(..)
   , Addr(..)
   )
where

import ViperVM.Arch.X86_64.Assembler.Size
import ViperVM.Arch.X86_64.Assembler.Registers
import ViperVM.Arch.X86_64.Assembler.ModRM

import Data.Word

data Op
   = OpImmediate SizedValue               -- ^ Immediate value
   | OpSignExtendImmediate SizedValue     -- ^ Sign-extended immediate value
   | OpReg Register                       -- ^ Register
   | OpMem Addr                           -- ^ Memory address
   | OpPtr16_16 !Word16 !Word16           -- ^ Immediate 16:16 ptr
   | OpPtr16_32 !Word16 !Word32           -- ^ Immediate 16:32 ptr
   | OpRel SizedValue                     -- ^ Immediate relative
   | OpMask SizedValue                    -- ^ Mask for vector operations

   | OpRegId !Word8                       -- ^ Register identifier (later to become a OpReg)
   deriving (Show,Eq)

-- The X86 architecture supports different kinds of memory addressing. The
-- available addressing modes depend on the execution mode.
-- The most complicated addressing has:
--    - a base register
--    - an index register with a scaling factor (1, 2, 4 or 8)
--    - an offset (displacement)
--
-- Base and index registers can be extended in 64-bit mode to access new registers.
-- Offset size depends on the address size and on the execution mode.

data Addr = Addr
   { addrBase  :: Maybe Register
   , addrIndex :: Maybe Register
   , addrDisp  :: Maybe SizedValue
   , addrScale :: Maybe Scale
   }
   deriving (Show,Eq)

-- | Operand types
data OperandType
   -- Immediates
   = T_Imm8       -- ^ Word8 immediate
   | T_Imm16      -- ^ Word16 immediate
   | T_Imm        -- ^ Variable sized immediate
   | T_REL_16_32  -- ^ Relative displacement (16-bit invalid in 64-bit mode)
   | T_PTR_16_16  -- ^ Absolute address
   | T_PTR_16_32  -- ^ Absolute address
   | T_Mask       -- ^ Mask for vectors

   -- General purpose registers
   | T_R          -- ^ General purpose register
   | T_R16        -- ^ 16-bit general purpose register
   | T_R32        -- ^ 32-bit general purpose register
   | T_RM         -- ^ Register or memory
   | T_RM16       -- ^ 16-bit general purpose register or memory
   | T_RM32       -- ^ 32-bit general purpose register or memory
   | T_RM16_32    -- ^ 16- or 32-bit general purpose register or memory
   | T_RM32_64    -- ^ 32- or 64-bit general purpose register or memory
   | T_RM16_32_64 -- ^ 16-, 32- or 64-bit general purpose register or memory
   | T_RM64       -- ^ 64-bit general purpose register or memory
   | T_R16_32     -- ^ 16- or 32-bit general purpose register
   | T_R32_64     -- ^ 32- or 64-bit general purpose register
   | T_R16_32_64  -- ^ 16-, 32- or 64-bit general purpose register

   -- Memory
   | T_M_PAIR     -- ^ Pair of words in memory (words are operand-size large)
   | T_M16_XX     -- ^ Pair of words in memory: m16:XX where XX can be 16, 32 or 64
   | T_M64_128    -- ^ 64- or 128-bit memory
   | T_M          -- ^ Any memory address
   | T_MFP        -- ^ Floating-point value in memory
   | T_M80dec     -- ^ Binary-coded decimal

   -- Vector registers
   | T_Vec           -- ^ Vector register (XMM, YMM, ZMM)
   | T_V64           -- ^ MMX Vector register
   | T_VM64          -- ^ MMX Vector register or 64-bit memory
   | T_V128          -- ^ XMM Vector register
   | T_VM128         -- ^ XMM Vector register or memory
   | T_V128_Low32    -- ^ Low 32-bits of a XMM Vector register
   | T_VM128_Low32   -- ^ Low 32-bits of a XMM Vector register or 32-bit memory
   | T_V128_Low64    -- ^ Low 64-bits of a XMM Vector register
   | T_VM128_Low64   -- ^ Low 64-bits of a XMM Vector register or 64-bit memory
   | T_V128_256      -- ^ XMM/YMM Vector register
   | T_VM128_256     -- ^ XMM/YMM Vector register or memory

   -- Specific registers
   | T_Accu       -- ^ Accumulator register (xAX)
   | T_AX_EAX_RAX -- ^ Accumulator registers except AL
   | T_xDX_xAX    -- ^ The pair (DX:AX), (EDX:EAX) or (RDX:RAX). If 8-bit mode is supported, it is only AX
   | T_xCX_xBX    -- ^ The pair (CX:BX), (ECX:EBX) or (RCX:RBX)
   | T_xAX        -- ^ EAX or RAX
   | T_xBX        -- ^ EBX or RBX
   | T_xCX        -- ^ ECX or RCX
   | T_xDX        -- ^ EDX or RDX
   | T_AL         -- ^ AL register
   | T_AX         -- ^ AX register
   | T_XMM0       -- ^ XMM0 register
   | T_rSI        -- ^ DS:rSI
   | T_rDI        -- ^ ES:rDI

   -- x87
   | T_ST0        -- ^ ST(0)
   | T_ST         -- ^ ST(i)
   | T_STMem      -- ^ ST(i) register or memory
   deriving (Show)

