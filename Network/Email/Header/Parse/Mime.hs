-- | Parsing of MIME header fields.
module Network.Email.Header.Parse.Mime
    ( mimeVersion
    , contentType
    ) where

import           Control.Applicative
import           Data.Attoparsec       (Parser)
import qualified Data.Attoparsec.Char8 as A8
import qualified Data.Map              as Map

import Network.Email.Header.Parse.Internal
import Network.Email.Types                 hiding (mimeType)

-- | Parse the MIME version (which should be 1.0).
mimeVersion :: Parser (Int, Int)
mimeVersion = (,) <$> digits 1 <* padded (A8.char '.') <*> digits 1

-- | Parse the content type.
contentType :: Parser (MimeType, Parameters)
contentType = (,) <$> mimeType <* cfws <*> parameters
  where
    mimeType   = MimeType <$> token <* padded (A8.char '/') <*> token
    parameters = Map.fromList <$> many (A8.char ';' *> padded parameter)
    parameter  = (,) <$> token <* padded (A8.char '=')
                     <*> (token <|> quotedString)
