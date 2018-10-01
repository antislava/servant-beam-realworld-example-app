module RealWorld.Conduit.Articles.Database.ArticleTag
  ( ArticleTagT(..)
  , ArticleTag
  ) where

import Control.Applicative ((<*>))
import Data.Eq (Eq)
import Data.Functor ((<$>))
import Database.Beam (Beamable, Identity, PrimaryKey, Table(..))
import GHC.Generics (Generic)
import RealWorld.Conduit.Articles.Database.Article (ArticleT)
import RealWorld.Conduit.Tags.Database.Tag (TagT)
import Text.Show (Show)

data ArticleTagT f = ArticleTag
  { article :: PrimaryKey ArticleT f
  , tag :: PrimaryKey TagT f
  } deriving (Generic)

type ArticleTag = ArticleTagT Identity

deriving instance Show ArticleTag

deriving instance Eq ArticleTag

instance Beamable ArticleTagT

instance Beamable (PrimaryKey ArticleTagT)

instance Table ArticleTagT where
  data PrimaryKey ArticleTagT f
    = ArticleTagId
        (PrimaryKey ArticleT f)
        (PrimaryKey TagT f)
    deriving Generic
  primaryKey =
    ArticleTagId
      <$> article
      <*> tag
