module Text.Parser.Monad where

open import Level using (Level)
open import Level.Bounded as Level≤ hiding (map)

open import Data.Char.Base using (Char)
open import Data.List.Base as List using ([]; _∷_; drop)
open import Data.Maybe.Base as Maybe using (nothing; just; maybe′)
open import Data.Product using (_,_; proj₁; proj₂; map₁; map₂)
open import Data.String.Base using (String)
open import Data.Text.Sized using (Text)

open import Data.Subset using (Subset; into)
open import Function.Base using (_∘′_; _$′_)

open import Effect.Functor
open import Effect.Applicative
open import Effect.Monad

open import Function.Identity.Effectful as Id using (Identity)
open import Effect.Monad.State

open import Relation.Binary.PropositionalEquality using (_≡_; refl; subst)

open import Relation.Unary
open import Text.Parser.Types.Core
open import Text.Parser.Types
open import Text.Parser.Position
open import Text.Parser.Monad.Result

private
  variable
    l : Level

--------------------------------------------------------------------------------
-- AGDARSECT

AgdarsecT : Set≤ l →           -- Error
            Set≤ l →           -- Annotation
            (Set l → Set l) → -- Monad
            (Set l → Set l)
AgdarsecT E Ann M = StateT (Lift ([ Position ] × List Ann)) (ResultT E M)

Agdarsec : (E : Set≤ l) (Ann : Set≤ l) → (Set l → Set l)
Agdarsec E Ann = AgdarsecT E Ann Identity

module AgdarsecT
        (E Ann : Set≤ l) {M : Set l → Set l}
        (𝕄 : RawMonad M)
        (𝕊 : Subset (theSet ([ Position ] × List Ann)) (theSet E))
        where

  private module 𝕄 = RawMonad 𝕄

  monadT : RawMonad (AgdarsecT E Ann M)
  monadT = StateTMonad _ (Result-monadT E 𝕄)

  applicative : RawApplicative (AgdarsecT E Ann M)
  applicative = RawMonad.rawIApplicative monadT

  applicativeZero : RawApplicativeZero (AgdarsecT E Ann M)
  applicativeZero = record
    { applicative = applicative
    ; ∅           = 𝕄.pure ∘′ SoftFail ∘′ Level≤.map (into 𝕊)
    }

  monadZero : RawMonadZero (AgdarsecT E Ann M)
  monadZero = record
    { monad           = monadT
    ; applicativeZero = applicativeZero
    }

  alternative : RawAlternative (AgdarsecT E Ann M)
  alternative = record
    { applicativeZero = applicativeZero
    ; _∣_             = λ ma₁ ma₂ s → ma₁ s 𝕄.>>= λ where
        (SoftFail _) → ma₂ s
        r            → 𝕄.pure r
    }

  monadPlus : RawMonadPlus (AgdarsecT E Ann M)
  monadPlus = record
    { monad       = monadT
    ; alternative = alternative
    }

  monadState : RawMonadState (Lift ([ Position ] × List Ann)) (AgdarsecT E Ann M)
  monadState = StateTMonadState _ (Result-monadT E 𝕄)

  private module ST = RawMonadState monadState

  getPosition : AgdarsecT E Ann M (Lift [ Position ])
  getPosition = Level≤.map proj₁ ST.<$> ST.get

  getAnnotations : AgdarsecT E Ann M (Lift (List Ann))
  getAnnotations = Level≤.map proj₂ ST.<$> ST.get

  withAnnotation : ∀ {A} → theSet Ann → AgdarsecT E Ann M A → AgdarsecT E Ann M A
  withAnnotation c ma = let open ST in do
    ST.modify (Level≤.map $′ map₂ (c ∷_))
    a ← ma
    ST.modify (Level≤.map $′ map₂ (drop 1))
    ST.pure a

  recordChar : Char → AgdarsecT E Ann M (Lift ⊤)
  recordChar c = _ ST.<$ ST.modify (Level≤.map $′ map₁ (update c))

  -- Commiting to a branch makes all the failures in that branch hard failures
  -- that we cannot recover from
  commit : ∀ {A} → AgdarsecT E Ann M A → AgdarsecT E Ann M A
  commit m s = result HardFail HardFail Value 𝕄.<$> m s

  param : ∀ Tok Toks recTok → Parameters l
  param Tok Toks recTok = record
    { Tok         = Tok
    ; Toks        = Toks
    ; M           = AgdarsecT E Ann M
    ; recordToken = recTok
    }

  chars : Parameters l
  chars = param [ Char ] (Vec [ Char ]) recordChar

  raw : Parameters l
  raw = param [ Char ] (λ n → [ Text n ]) recordChar

module Agdarsec l (E Ann : Set≤ l) (𝕊 : Subset (theSet ([ Position ] × List Ann)) (theSet E)) where

  private module M = AgdarsecT E Ann Id.monad 𝕊
  open M public renaming (monadT to monad) hiding (commit)

  module _ {Tok Toks recTok} where

    private P = param Tok Toks recTok
    commit : {A : Set≤ l} → ∀[ Parser P A ⇒ Parser P A ]
    runParser (commit p) m≤n s = M.commit (runParser p m≤n s)

module Agdarsec′ {l : Level} where

  open Agdarsec l ⊤ ⊥ _ public

  vec : Set≤ l → Parameters l
  vec Tok = record
    { Tok         = Tok
    ; Toks        = Vec Tok
    ; M           = Agdarsec ⊤ ⊥
    ; recordToken = λ _ → M.pure _
    } where module M = RawMonad monad

  txt : Set≤ l → Parameters l
  txt Tok = record
    { Tok         = Tok
    ; Toks        = λ n → [ Text n ]
    ; M           = Agdarsec ⊤ ⊥
    ; recordToken = λ _ → M.pure _
    } where module M = RawMonad monad
