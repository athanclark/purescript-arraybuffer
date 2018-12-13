module Test.Properties.TypedArray where


import Data.ArrayBuffer.Types (ArrayView)
import Data.ArrayBuffer.Typed as TA
import Data.ArrayBuffer.Typed (class BytesPerValue, class TypedArray)
import Data.ArrayBuffer.Typed.Gen
  ( genUint8ClampedArray, genUint8Array, genUint16Array, genUint32Array
  , genInt8Array, genInt16Array, genInt32Array
  , genFloat32Array, genFloat64Array, WithOffset (..), genWithOffset)

import Prelude
import Data.Maybe (Maybe (..))
import Data.Tuple (Tuple (..))
import Data.Typelevel.Num (toInt', class Nat, D0, D1, D5)
import Data.Vec (head) as Vec
import Data.Array as Array
import Data.HeytingAlgebra (implies)
import Type.Proxy (Proxy (..))
import Test.QuickCheck (quickCheckGen, Result (..), (===), class Testable, class Arbitrary, (<?>))
import Test.QuickCheck.Combinators ((&=&), (|=|), (==>))
import Effect (Effect)
import Effect.Unsafe (unsafePerformEffect)
import Effect.Console (log)


typedArrayTests :: Effect Unit
typedArrayTests = do
  log "    - byteLength x / bytesPerValue === length x"
  byteLengthDivBytesPerValueTests
  log "    - fromArray (toArray x) === x"
  fromArrayToArrayIsoTests
  log "    - fill y x => all (== y) x"
  allAreFilledTests
  log "    - set x [y] o => (at x o == Just y)"
  setSingletonIsEqTests
  log "    - all p x => any p x"
  allImpliesAnyTests
  log "    - all p (filter p x)"
  filterImpliesAllTests
  log "    - filter (not . p) (filter p x) == []"
  filterIsTotalTests
  log "    - filter p (filter p x) == filter p x"
  filterIsIdempotentTests
  log "    - forall os `in` xs. all (\\o -> hasIndex o xs)"
  withOffsetHasIndexTests
  log "    - forall os `in` xs. all (\\o -> elem (at o xs) xs)"
  withOffsetElemTests
  log "    - any p x => p (find p x)"
  anyImpliesFindTests
  log "    - p (at x (findIndex p x))"
  findIndexImpliesAtTests
  log "    - at x (indexOf y x) == y"
  indexOfImpliesAtTests
  log "    - at x (lastIndexOf y x) == y"
  lastIndexOfImpliesAtTests


-- TODO: folding, traversals, mapping
--       copyWithin, reverse, sort, setTyped, slice, subArray
--       toString ~ join ","



type TestableArrayF a b n t q =
     Show t
  => Eq t
  => TypedArray a t
  => Nat b
  => BytesPerValue a b
  => Arbitrary t
  => Semiring t
  => WithOffset n a
  -> q


overAll :: forall q n. Testable q => Nat n => (forall a b t. TestableArrayF a b n t q) -> Effect Unit
overAll f = do
  log "      - Uint8ClampedArray"
  quickCheckGen (f <$> genWithOffset genUint8ClampedArray)
  log "      - Uint32Array"
  quickCheckGen (f <$> genWithOffset genUint32Array)
  log "      - Uint16Array"
  quickCheckGen (f <$> genWithOffset genUint16Array)
  log "      - Uint8Array"
  quickCheckGen (f <$> genWithOffset genUint8Array)
  log "      - Int32Array"
  quickCheckGen (f <$> genWithOffset genInt32Array)
  log "      - Int16Array"
  quickCheckGen (f <$> genWithOffset genInt16Array)
  log "      - Int8Array"
  quickCheckGen (f <$> genWithOffset genInt8Array)
  log "      - Float32Array"
  quickCheckGen (f <$> genWithOffset genFloat32Array)
  log "      - Float64Array"
  quickCheckGen (f <$> genWithOffset genFloat64Array)


byteLengthDivBytesPerValueTests :: Effect Unit
byteLengthDivBytesPerValueTests = overAll byteLengthDivBytesPerValueEqLength
  where
    byteLengthDivBytesPerValueEqLength :: forall a b t. TestableArrayF a b D0 t Result
    byteLengthDivBytesPerValueEqLength (WithOffset _ a) =
      let b = toInt' (Proxy :: Proxy b)
      in  TA.length a === (TA.byteLength a `div` b)

fromArrayToArrayIsoTests :: Effect Unit
fromArrayToArrayIsoTests = overAll fromArrayToArrayIso
  where
    fromArrayToArrayIso :: forall a b t. TestableArrayF a b D0 t Result
    fromArrayToArrayIso (WithOffset _ x) =
      TA.toArray (TA.fromArray (TA.toArray x) :: ArrayView a) === TA.toArray x


allAreFilledTests :: Effect Unit
allAreFilledTests = overAll allAreFilled
  where
    allAreFilled :: forall a b t. TestableArrayF a b D0 t Result
    allAreFilled (WithOffset _ xs) = unsafePerformEffect do
      let x = case TA.at xs 0 of
            Nothing -> zero
            Just y -> y
      TA.fill xs x Nothing
      b <- TA.all (\y o -> pure (y == x)) xs
      pure (b === true)


setSingletonIsEqTests :: Effect Unit
setSingletonIsEqTests = overAll setSingletonIsEq
  where
    setSingletonIsEq :: forall a b t. TestableArrayF a b D1 t Result
    setSingletonIsEq (WithOffset os xs) = unsafePerformEffect do
      let x = case TA.at xs 0 of
            Nothing -> zero
            Just y -> y
      TA.set xs (Just (Vec.head os)) [x]
      pure (TA.at xs (Vec.head os) === Just x)


-- | Should work with any arbitrary predicate, but we can't generate them
allImpliesAnyTests :: Effect Unit
allImpliesAnyTests = overAll allImpliesAny
  where
    allImpliesAny :: forall a b t. TestableArrayF a b D0 t Result
    allImpliesAny (WithOffset _ xs) =
      let pred x o = pure (x /= zero)
          all' = unsafePerformEffect (TA.all pred xs)
          any' = unsafePerformEffect (TA.any pred xs)
      in  all' `implies` any' <?> "All doesn't imply any"


-- | Should work with any arbitrary predicate, but we can't generate them
filterImpliesAllTests :: Effect Unit
filterImpliesAllTests = overAll filterImpliesAll
  where
    filterImpliesAll :: forall a b t. TestableArrayF a b D0 t Result
    filterImpliesAll (WithOffset _ xs) =
      let pred x o = pure (x /= zero)
          ys = unsafePerformEffect (TA.filter pred xs)
          all' = unsafePerformEffect (TA.all pred ys)
      in  all' <?> "Filter doesn't imply all"


-- | Should work with any arbitrary predicate, but we can't generate them
filterIsTotalTests :: Effect Unit
filterIsTotalTests = overAll filterIsTotal
  where
    filterIsTotal :: forall a b t. TestableArrayF a b D0 t Result
    filterIsTotal (WithOffset _ xs) =
      let pred x o = pure (x /= zero)
          ys = unsafePerformEffect (TA.filter pred xs)
          zs = unsafePerformEffect (TA.filter (\x o -> not <$> pred x o) ys)
      in  TA.toArray zs === []


-- | Should work with any arbitrary predicate, but we can't generate them
filterIsIdempotentTests :: Effect Unit
filterIsIdempotentTests = overAll filterIsIdempotent
  where
    filterIsIdempotent :: forall a b t. TestableArrayF a b D0 t Result
    filterIsIdempotent (WithOffset _ xs) =
      let pred x o = pure (x /= zero)
          ys = unsafePerformEffect (TA.filter pred xs)
          zs = unsafePerformEffect (TA.filter pred ys)
      in  TA.toArray zs === TA.toArray ys


withOffsetHasIndexTests :: Effect Unit
withOffsetHasIndexTests = overAll withOffsetHasIndex
  where
    withOffsetHasIndex :: forall a b t. TestableArrayF a b D5 t Result
    withOffsetHasIndex (WithOffset os xs) =
      Array.all (\o -> TA.hasIndex xs o) os <?> "All doesn't have index of itself"


withOffsetElemTests :: Effect Unit
withOffsetElemTests = overAll withOffsetElem
  where
    withOffsetElem :: forall a b t. TestableArrayF a b D5 t Result
    withOffsetElem (WithOffset os xs) =
      Array.all (\o -> TA.elem (unsafePerformEffect (TA.unsafeAt xs o)) Nothing xs) os
        <?> "All doesn't have an elem of itself"


-- | Should work with any arbitrary predicate, but we can't generate them
anyImpliesFindTests :: Effect Unit
anyImpliesFindTests = overAll anyImpliesFind
  where
    anyImpliesFind :: forall a b t. TestableArrayF a b D0 t Result
    anyImpliesFind (WithOffset _ xs) =
      let pred x o = pure (x /= zero)
          q = unsafePerformEffect (TA.any pred xs)
          is = unsafePerformEffect do
            mzs <- TA.find xs pred
            case mzs of
              Nothing -> pure Nothing
              Just z -> Just <$> pred z 0
      in  q `implies` (Just true == is) <?> "Any imples find"


-- | Should work with any arbitrary predicate, but we can't generate them
findIndexImpliesAtTests :: Effect Unit
findIndexImpliesAtTests = overAll findIndexImpliesAt
  where
    findIndexImpliesAt :: forall a b t. TestableArrayF a b D0 t Result
    findIndexImpliesAt (WithOffset _ xs) =
      let pred x o = pure (x /= zero)
          mo = unsafePerformEffect (TA.findIndex xs pred)
      in  case mo of
            Nothing -> Success
            Just o -> case TA.at xs o of
              Nothing -> Failed "No value at found index"
              Just x -> unsafePerformEffect (pred x o) <?> "Find index implies at"



indexOfImpliesAtTests :: Effect Unit
indexOfImpliesAtTests = overAll indexOfImpliesAt
  where
    indexOfImpliesAt :: forall a b t. TestableArrayF a b D0 t Result
    indexOfImpliesAt (WithOffset _ xs) =
      case TA.at xs 0 of
        Nothing -> Success
        Just y -> case TA.indexOf xs y Nothing of
          Nothing -> Failed "no index of"
          Just o -> TA.at xs o === Just y


lastIndexOfImpliesAtTests :: Effect Unit
lastIndexOfImpliesAtTests = overAll lastIndexOfImpliesAt
  where
    lastIndexOfImpliesAt :: forall a b t. TestableArrayF a b D0 t Result
    lastIndexOfImpliesAt (WithOffset _ xs) =
      case TA.at xs 0 of
        Nothing -> Success
        Just y -> case TA.lastIndexOf xs y Nothing of
          Nothing -> Failed "no lastIndex of"
          Just o -> TA.at xs o === Just y
