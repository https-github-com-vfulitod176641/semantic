module CorpusSpec where

import Diffing
import Renderer
import Unified

import Data.Bifunctor.Join
import qualified Data.ByteString.Char8 as B1
import Data.List as List
import Data.Map as Map
import Data.Set as Set
import qualified Data.Text as T
import Rainbow
import System.FilePath
import System.FilePath.Glob
import Test.Hspec

spec :: Spec
spec = do
  describe "crashers should not crash" $ runTestsIn "test/crashers/"
  describe "should produce the correct diff" $ runTestsIn "test/diffs/"

  it "lists example fixtures" $ do
    examples "test/crashers/" `shouldNotReturn` []
    examples "test/diffs/" `shouldNotReturn` []

  where
    runTestsIn directory = do
      tests <- runIO $ examples directory
      mapM_ (\ (a, b, diff) -> it (normalizeName a) $ testDiff testUnified a b diff `shouldReturn` True) tests
    testUnified :: Renderer a String
    testUnified diff sources = B1.unpack $ mconcat $ chunksToByteStrings toByteStringsColors0 $ unified diff sources


-- | Return all the examples from the given directory. Examples are expected to
-- | have the form "foo.A.js", "foo.B.js", "foo.diff.js". Diffs are not
-- | required as the test may be verifying that the inputs don't crash.
examples :: FilePath -> IO [(FilePath, FilePath, Maybe FilePath)]
examples directory = do
  as <- toDict <$> globFor "*.A.*"
  bs <- toDict <$> globFor "*.B.*"
  unifieds <- toDict <$> globFor "*.unified.*"
  let keys = Set.unions $ keysSet <$> [as, bs]
  return $ (\name -> (as ! name, bs ! name, Map.lookup name unifieds)) <$> sort (Set.toList keys)

  where
    globFor :: String -> IO [FilePath]
    globFor p = globDir1 (compile p) directory
    toDict list = Map.fromList ((normalizeName <$> list) `zip` list)

-- | Given a test name like "foo.A.js", return "foo.js".
normalizeName :: FilePath -> FilePath
normalizeName path = addExtension (dropExtension $ dropExtension path) (takeExtension path)

-- | Given file paths for A, B, and, optionally, a diff, return whether diffing
-- | the files will produce the diff. If no diff is provided, then the result
-- | is true, but the diff will still be calculated.
testDiff :: Renderer T.Text String -> FilePath -> FilePath -> Maybe FilePath -> IO Bool
testDiff renderer a b diff = do
  let parser = parserForFilepath a
  sources <- sequence $ readAndTranscodeFile <$> Join (a, b)
  actual <- diffFiles parser renderer (runJoin sources)
  case diff of
    Nothing -> return $ actual /= "<should not be a thing>"
    Just file -> do
      expected <- readFile file
      return $ expected == actual
