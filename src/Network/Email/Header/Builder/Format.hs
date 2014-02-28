{-# LANGUAGE OverloadedStrings #-}
module Network.Email.Header.Builder.Format
    ( -- * Date and time
      dateTime
      -- * Addresses
    , address
    , mailbox
    , mailboxList
    , recipient
    , recipientList
      -- * Message IDs
    , messageID
    , messageIDList
      -- * Text
    , phrase
    , phraseList
    , unstructured
      -- * MIME
    , mimeVersion
    , contentType
    , contentTransferEncoding
    ) where

import qualified Data.ByteString              as B
import qualified Data.ByteString.Lazy.Builder as B
import qualified Data.ByteString.Lazy         as LB
import           Data.List                    (intersperse)
import           Data.Monoid
import           Data.String
import           Data.Time
import qualified Data.Text.Lazy               as L
import qualified Data.Text.Lazy.Encoding      as L
import           Data.Time.LocalTime
import           System.Locale

import           Network.Email.Format         (Layout, Doc)
import qualified Network.Email.Format         as F
import           Network.Email.Types

infixr 6 </>

data RenderOptions = RenderOptions
    { lineWidth :: Int
    , indent    :: Int
    } deriving (Eq, Read, Show)

-- | A header builder.
newtype Builder = Builder { runBuilder :: RenderOptions -> Doc B.Builder }

instance Monoid Builder where
    mempty      = Builder $ \_ -> mempty
    mappend a b = Builder $ \r -> runBuilder a r <> runBuilder b r

instance IsString Builder where
    fromString s = builder (length s) (B.string8 s)

-- | Construct a 'Builder' from a 'B.Builder'.
builder :: Int -> B.Builder -> Builder
builder k s = Builder $ \_ -> F.prim $ \_ -> F.span k s

-- | Construct a 'Builder' from a 'B.ByteString'.
byteString :: B.ByteString -> Builder
byteString s = builder (B.length s) (B.byteString s)

-- | Construct a 'Builder' from a 'L.Text'.
text :: L.Text -> Builder
text = byteString . LB.toStrict . L.encodeUtf8

-- | Group 'Builder's.
group :: Builder -> Builder
group a = Builder $ \r -> F.group (runBuilder a r)

-- | A space layout.
space :: Layout B.Builder
space = F.span 1 (B.char8 ' ')

-- | A newline layout.
newline :: RenderOptions -> Layout B.Builder
newline r =
    F.span 2 (B.byteString "\r\n") <>
    F.break 0 <>
    mconcat (replicate (indent r) space)

-- | A line break. If undone, behaves like a space.
line :: Builder
line = Builder $ \r -> F.prim $ \h -> if h then space else newline r

-- | A line break. If undone, behaves like `mempty`.
linebreak :: Builder
linebreak = Builder $ \r -> F.prim $ \h -> if h then mempty else newline r

-- | A line break or a space.
softline :: Builder
softline = group line

-- | A line break or `mempty`.
softbreak :: Builder
softbreak = group linebreak

-- | Concatenate with a 'softline' in between.
(</>) :: Builder -> Builder -> Builder
a </> b = a <> softline <> b

-- | Separate with lines or spaces.
sep :: [Builder] -> Builder
sep = group . mconcat . intersperse line

-- | Format an integer.
int :: Int -> Builder
int = fromString . show

-- | @punctuate p xs@ appends @p@ to every element of @xs@ but the last.
punctuate :: Monoid a => a -> [a] -> [a]
punctuate p = go
  where
    go []     = []
    go [x]    = [x]
    go (x:xs) = x <> p : xs

-- | Separate a group with commas.
commaSep :: (a -> Builder) -> [a] -> Builder
commaSep f = sep . punctuate "," . map f

-- | Format a date and time.
dateTime :: ZonedTime -> Builder
dateTime = fromString . formatTime defaultTimeLocale rfc822DateFormat

-- | Format an address.
address :: Address -> Builder
address (Address s) = byteString s

-- | Format an address with angle brackets.
angleAddr :: Address -> Builder
angleAddr a = "<" <> address a <> ">"

-- | Format a 'Mailbox'.
mailbox :: Mailbox -> Builder
mailbox (Mailbox n a) = case n of
    Nothing   -> address a
    Just name -> phrase name </> angleAddr a

-- | Format a list of 'Mailbox'es.
mailboxList :: [Mailbox] -> Builder
mailboxList = commaSep mailbox

-- | Format a 'Recipient'.
recipient :: Recipient -> Builder
recipient (Individual m)  = mailbox m
recipient (Group name ms) = phrase name <> ":" </> mailboxList ms

-- | Format a list of 'Recipient'es.
recipientList :: [Recipient] -> Builder
recipientList = commaSep recipient

-- | Format a message identifier
messageID :: MessageID -> Builder
messageID (MessageID s) = byteString s

-- | Format a list of message identifiers.
messageIDList :: [MessageID] -> Builder
messageIDList = commaSep messageID

-- | Encode text as an encoded word.
encodeText :: L.Text -> Builder
encodeText = undefined

-- | Encode text, given a predicate that checks for illegal characters.
renderText :: (Char -> Bool) -> L.Text -> Builder
renderText isIllegalChar t
    | mustEncode = encodeText t
    | otherwise  = sep (map text ws)
  where
    ws         = L.words t

    mustEncode = L.unwords ws /= t
              || any ("=?" `L.isPrefixOf`) ws
              || L.any isIllegalChar t

-- | Format a phrase. The text is encoded as is, unless:
-- * The text opens or closes with whitespace, or more than one space appears in
--   between words
-- * Any word begins with =?
-- * Any word contains illegal characters
phrase :: L.Text -> Builder
phrase = renderText (\c -> c > '~' || c < '!' || c `elem` "()<>[]:;@\\\",")

-- | Format a list of phrases.
phraseList :: [L.Text] -> Builder
phraseList = commaSep phrase

-- | Format unstructured text. The text is encoded as is, unless:
-- * The text opens or closes with whitespace, or more than one space appears in
--   between words
-- * Any word begins with =?
-- * Any word contains illegal characters
unstructured :: L.Text -> Builder
unstructured = renderText (\c -> c > '~' || c < '!')

-- | Format the MIME version.
mimeVersion ::  Int -> Int -> Builder
mimeVersion major minor = int major <> "." <> int minor

-- | Format the content type and parameters.
contentType :: MimeType -> Parameters -> Builder
contentType = undefined

-- | Format the content transfer encoding.
contentTransferEncoding :: B.ByteString -> Builder
contentTransferEncoding = byteString
