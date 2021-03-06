{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE StaticPointers #-}
{-# LANGUAGE TupleSections #-}

{-
This application will process every public GitHub event occured in 2019 to get
the top 20 users who used the word "cabal" in their commit messages the most.

This will download and process around 126 GB of compressed, 909 GB uncompressed
data; and it'll set you back a few dollars on your AWS bill.
-}
module Main where

import Control.Distributed.Dataset
import Control.Distributed.Dataset.AWS
import Control.Distributed.Dataset.OpenDatasets.GHArchive
import Control.Lens
import qualified Data.Text as T
import System.Environment (getArgs)

app :: DD ()
app =
  -- Fetch events from GitHub between given dates
  ghArchive (fromGregorian 2019 1 1, fromGregorian 2019 12 31)
    -- Extract every commit
    & dConcatMap
      ( static
          ( \e ->
              let author = e ^. gheActor . ghaLogin
                  commits =
                    e ^.. gheType . _GHPushEvent . ghpepCommits
                      . traverse
                      . ghcMessage
               in maybe [] (\a -> map (a,) commits) author
          )
      )
    -- Filter commits containing the word 'cabal'
    & dFilter
      ( static
          ( \(_, commit) ->
              "cabal" `T.isInfixOf` T.toLower commit
          )
      )
    -- Count the authors
    & dGroupedAggr 50 (static fst) aggrCount
    -- Fetch the top 20 to driver as a list
    & dAggr (aggrTopK (static Dict) 20 (static snd))
    -- Print them
    >>= mapM_ (liftIO . print)

main :: IO ()
main = do
  initDistributedFork
  args <- getArgs
  bucket <-
    case args of
      [bucket'] -> return $ T.pack bucket'
      _ -> error "Usage: ./gh <bucket>"
  withLambdaBackend (lambdaBackendOptions bucket) $ \backend -> do
    let shuffleStore = s3ShuffleStore bucket "dd-shuffle-store/"
    runDD backend shuffleStore app
