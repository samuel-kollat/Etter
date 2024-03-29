-- VYSOKE UCENI TECHNICKE V BRNE
-- Fakulta informacnich technologii

-- Projekt FLP: Interpret imperativneho jazyka FLP-2014-C
-- Autori: [VEDUCI] Bc. Antolik David, xantol01@stud.fit.vutbr.cz
--         Bc. Kollar Jaroslav, xkolla03@stud.fit.vutbr.cz
--         Bc. Kollat Samuel, xkolla04@stud.fit.vutbr.cz
--         Bc. Kovacik Dusan, xkovac34@stud.fit.vutbr.cz

module Main( main ) where

import System.Environment( getArgs )
import System.IO

import Text.ParserCombinators.Parsec
import qualified Text.ParserCombinators.Parsec.Token as P
import Text.ParserCombinators.Parsec.Expr
import Text.ParserCombinators.Parsec.Language

-- Lexikalna analyza
aelDef = emptyDef
    { commentStart   = "/*"
    , commentEnd     = "*/"
    , commentLine    = "//"
    , nestedComments = False
    , identStart     = letter <|> char '_'
    , identLetter    = alphaNum <|> char '_'
    , opStart        = oneOf "=+*-!><"
    , opLetter       = opStart aelDef
    , reservedOpNames= [ "=", "+", "*", "-", "/", "==", "!=", "<", "<=", ">=", ">" ]
    , reservedNames  = [ "double", "else", "if", "int", "print", "scan", "string", "while", "return" ]
    , caseSensitive  = True
    }

-- Lexikalny analyzator
lexer = P.makeTokenParser aelDef

-- Pomocne funkcie lexikalnej analyzy
whiteSpace = P.whiteSpace lexer
integer    = P.integer lexer
intOrFloat = P.naturalOrFloat lexer
stringLit  = P.stringLiteral lexer
parens     = P.parens lexer
braces     = P.braces lexer
semi       = P.semi lexer
identifier = P.identifier lexer
reserved   = P.reserved lexer
reservedOp = P.reservedOp lexer
comma      = P.comma lexer

-- Definicia hodnot
data Value = 
      ValInt Int
    | ValDouble Double
    | ValString String
    deriving (Show, Eq, Ord)

-- Definicia vyrazov
data Expr =
    Const Value
  | Var String
  | Fun String [Arg]
  | Add Expr Expr
  | Sub Expr Expr
  | Mult Expr Expr
  | Div Expr Expr
  | Gt Expr Expr
  | GtEq Expr Expr
  | Lt Expr Expr
  | LtEq Expr Expr
  | Eq Expr Expr
  | Neq Expr Expr
  deriving (Show, Eq)

-- Ziskanie typu premennej, funkcie
getType = do
        reserved "int"
        return Int
    <|> do
        reserved "double"
        return Double
    <|> do
        reserved "string"
        return String

-- Ziskanie paramatrov funkcie pri jej deklaracii, definicii
getMoreParams t i = do
        comma
        p <- getNoEmptyParams
        return $ (Param t i):p
    <|> do
        return $ [(Param t i)]

getParams = do
        t <- getType
        i <- identifier
        getMoreParams t i
    <|> do
        return []

getNoEmptyParams = do
        t <- getType
        i <- identifier
        getMoreParams t i

-- Ziskanie argumentov funkcie pri jej volani
getMoreFuncArgs e = do
        comma
        a <- getNoEmptyFuncArgs
        return $ (Arg e):a
    <|> do
        return $ [(Arg e)]


getFuncArgs = do
        e <- expr
        getMoreFuncArgs e
    <|> do
        return []

getNoEmptyFuncArgs = do
        e <- expr
        getMoreFuncArgs e

-- Precedencna analyza vyrazov
expr = buildExpressionParser operators term where
  operators = [
      [ op "*" Mult, op "/" Div ],
      [ op "+" Add, op "-" Sub ],
      [ op "<" Lt, op "<=" LtEq, op ">" Gt, op ">=" GtEq, op "==" Eq, op "!=" Neq]
    ]
  op name fun =
    Infix ( do { reservedOp name; return fun } ) AssocLeft

-- Spracovanie vyrazu pomocou definovanych datovych typov
term_ident i =
    do
        a <- parens $ getFuncArgs
        return $ Fun i a
    <|> do
        return $ Var i

term = do
    f <- intOrFloat
    case f of 
        Left i -> return $ Const $ ValInt $ fromInteger i
        Right d -> return $ Const $ ValDouble d    
  <|> do
    s <- stringLit
    return $ Const $ ValString s
  <|> do
    i <- identifier
    term_ident i
  <|> parens expr
  <?> "term"

-- Definicia struktury prikazov jazyka
data Cmd =
      Empty                             -- prazdny prikaz
    | IfStmt Expr Cmd Cmd               -- if
    | WhileStmt Expr Cmd                -- while
    | Func Type String [Param] Cmd      -- definicia funkcie
    | FuncDecl Type String [Param]      -- deklaracia funkcie (bez tela)
    | FuncCall String [Arg]             -- volanie funkcie
    | AssignStmt String Expr            -- priradenie premennej
    | VarDefStmt Type String            -- deklaracia premennej v bloku
    | VarDefStmtAssign Type String Expr -- deklaracia a definicia premennej v bloku
    | ReturnStmt Expr                   -- navrat z funkcie
    | Print Expr                        -- vstavana funkcia Print
    | Scan String                       -- vstavana funkcia Scan
    | Seq [Cmd]                         -- zlozeny prikaz
    deriving (Show, Eq)

-- Datove typy v jazyku
data Type =
      String
    | Int
    | Double    
    deriving (Show, Eq)

-- Struktura parametrov funkcie
data Param = Param Type String
    deriving (Show, Eq)

-- Struktura argumentov predavanych do funkcie
data Arg = Arg Expr
    deriving (Show, Eq)

-- Syntakticka analyza

command_ident i =
    do                                  -- id ( args_list )
        a <- parens $ getFuncArgs
        semi
        return $ FuncCall i a 
    <|> do                              -- id = expr ;
        reservedOp "="
        e <- expr
        semi
        return $ AssignStmt i e
        
command_if_else b c1 =
    do
        reserved "else"
        c2 <- command_local_body
        return $ IfStmt b c1 c2
    <|> do
        return $ IfStmt b c1 (Seq [Empty])

command_local_body = 
    do                                  -- id ( args_list ) ; id = expr ;
        i <- identifier
        command_ident i
    <|> do                              -- return expr ;
        reserved "return"
        e <- expr
        semi
        return $ ReturnStmt e
    <|> do                              -- print ( expr ) ;
        reserved "print"
        e <- parens $ expr
        semi
        return $ Print e
    <|> do                              -- scan ( expr ) ;
        reserved "scan"
        i <- parens $ identifier
        semi
        return $ Scan i
    <|> do                              -- if ( expr ) { command_list } else { command_list }
        reserved "if"
        b <- parens $ expr
        c1 <- command_local_body
        command_if_else b c1
    <|> do                              -- while ( expr ) { command_list }
        reserved "while"
        b <- parens $ expr
        c <- command_local_body
        return $ WhileStmt b c
    <|> do                              -- { command_list }
        seq <- braces $ many command_local_body
        return $ Seq seq

command_local_decl_def t i =
    do
        semi
        return $ VarDefStmt t i         -- typ id;
    <|> do
        reservedOp "="
        e <- expr
        semi                            -- typ id = expr;
        return $ VarDefStmtAssign t i e

command_local_decl = 
    do
        semi
        return Empty
    <|> do                            
        t <- getType
        i <- identifier
        command_local_decl_def t i
        
command_local_tog = 
    do
        seq_dec <- many command_local_decl
        seq_body <- many command_local_body
        return $ seq_dec ++ seq_body
        
command_local = 
    do                                  -- { command_list }
        seq <- braces $ command_local_tog
        return $ Seq seq

command_func t i p =
    do                                  -- return_type id ( params_list ) ;
        semi
        return $ FuncDecl t i p
    <|> do                              -- return_type id ( params_list ) { command_list }
        c <- command_local
        return $ Func t i p c

command_global_ident t i =
    do
        semi
        return $ VarDefStmt t i
    <|> do
        reservedOp "="
        e <- expr
        semi
        return $ VarDefStmtAssign t i e
    <|> do
        params <- parens getParams
        command_func t i params

command_global_decl =
    do
        semi
        return Empty
    <|> do                              -- typ id ;
        t <- getType
        i <- identifier
        command_global_ident t i

command_global =
    do
        seq_global <- many command_global_decl
        return $ seq_global

command =
    do                                  -- program
        seq <- braces $ command_global
        return $ Seq seq
    <?> "command"
        
        
        
-- Tabulka premennych
type VarTable = [(String, Value)]

-- nastavenie premennej a jej hodnoty v tabulke premennych
setVar :: VarTable -> String -> Value -> VarTable
setVar [] var val = [(var, val)]
setVar (s@(v,vT):ss) var val =
    if v == var
        then typeCorrect vT val 
        else s : setVar ss var val
    where -- overovanie typov pri priradeni hodnoty do premennej.
        typeCorrect (ValInt i1) (ValInt i2) = (var, val):ss
        typeCorrect (ValDouble i1) (ValInt i2) = (var, ValDouble $ fromIntegral i2):ss
        typeCorrect (ValDouble i1) (ValDouble i2) = (var, val):ss
        typeCorrect (ValString i1) (ValString i2) = (var, val):ss
        typeCorrect _ _ = error $ "Type missmatch in setting variable :" ++ var 
            
-- ziskanie hodnoty premennej z tabulky premennych
getVar :: VarTable -> String -> Value
getVar [] v = error $ "Variable not found in symbol table: " ++ v
getVar (s@(var, val):ss) v =
    if v == var
        then val
        else getVar ss v
        
-- overenie, ci je premenna v tabulke premennych
isVar :: VarTable -> String -> Bool
isVar [] n = False
isVar ((name, val):vs) n
    | name == n = True
    | otherwise = isVar vs n

-- Zaznam funkcie
data FuncRecord =   FuncRecord
                    { funcName      :: String
                    , funcType      :: Type
                    , funcParams    :: [Param]
                    , funcCommands  :: Cmd
                    } deriving Show

-- Tabulka funkcii
type FuncTable = [FuncRecord]

-- Kontrola originality nazvov premennych v parametroch
originalParametersTest :: [Param] -> [String] -> [Param]
originalParametersTest [] _ = []
originalParametersTest ((Param ptype pname):ps) ls = if isInList pname ls
                                                 then error "Multiple parameters with same name!"
                                                 else ((Param ptype pname):originalParametersTest ps (pname:ls))
    
-- pridanie funkcie do tabulky funkcii, vratane nazvu, navratoveho typu, parametrov a zoznamu prikazov
setFunc :: FuncTable -> String -> Type -> [Param] -> Cmd -> Bool -> FuncTable
setFunc [] n t ps c b       -- ak je Bool (pred main) True, potom uloz, inak neukladaj
    | b == True = [FuncRecord {funcName=n, funcType=t, funcParams=originalParametersTest ps [], funcCommands=c}]
    | otherwise = []
setFunc ft@(f:fs) n t ps c b
    | funcName f == n = updateFunc f t (originalParametersTest ps []) c
    | otherwise = f : setFunc fs n t ps c b
    where
        updateFunc f t ps c = 
            if funcType f == t
            then
                if funcParams f == ps
                then
                    if funcCommands f == Empty
                    then
                        if c /= Empty
                        then
                            FuncRecord {funcName=n, funcType=t, funcParams=ps, funcCommands=c} : fs
                        else
                          error $ "Multiple declarations of function: " ++ funcName f  
                    else
                      error $ "Multiple definitions of function: " ++ funcName f  
                else
                  error $ "Multiple declarations of function with different parameters: " ++ funcName f  
            else
                error $ "Multiple declarations of function with different types: " ++ funcName f

-- ziskanie navratoveho typu funkcie
getFuncType :: FuncTable -> String -> Type
getFuncType [] fName = error $ "Cannot access type of function: " ++ fName
getFuncType (f:fs) fName
    | funcName f == fName = funcType f
    | otherwise = getFuncType fs fName

-- vyhodnotenie funkcie s danymi argumentami a uprava tabulky symbolov
getFuncResult :: SymTable -> FuncTable -> String -> [Arg] -> IO SymTable
getFuncResult _ [] fName _ = error $ "Undefined function call: " ++ fName
getFuncResult st@(gt, ft, lt, gc) (f:fs) fName fArgs
    | funcName f == fName = do
            (gt', ltTable) <- assignArgsToParams st [] fName (funcParams f) fArgs
            if (funcCommands f) == Empty
            then
                error $ "Undefined function " ++ fName
            else do
                (st,_) <- interpret (gt', ft, ltTable, gc) (funcCommands f)
                return st
    | otherwise = getFuncResult st fs fName fArgs

-- priradenie argumentov do parametrov funkcie, ktora vracia globalnu a lokalnu tabulku premennych
assignArgsToParams :: SymTable -> VarTable -> String -> [Param] -> [Arg] -> IO (VarTable, VarTable)
assignArgsToParams (gt, _, _, _) vt _ [] [] = return (gt, vt)
assignArgsToParams _ _ n (p:ps) [] = error $ "Function called with less argumegt than required: " ++ n
assignArgsToParams _ _ n [] (arg:args) = error $ "Function called with more argumegt than required: " ++ n
assignArgsToParams st@(gt', ft', lt', gc') vt n ((Param pType pName):ps) ((Arg ex):args) = do
    (gt, evaluated) <- eval st ex
    case (pType, evaluated) of
        (Int, ValInt val)       -> assignArgsToParams (gt, ft', lt', gc') (setVar vt pName $ ValInt val) n ps args
        (Double, ValInt val)    -> assignArgsToParams (gt, ft', lt', gc') (setVar vt pName $ ValDouble $ fromIntegral val) n ps args
        (Double, ValDouble val) -> assignArgsToParams (gt, ft', lt', gc') (setVar vt pName $ ValDouble val) n ps args
        (String, ValString val) -> assignArgsToParams (gt, ft', lt', gc') (setVar vt pName $ ValString val) n ps args
        _   -> error $ "Passing parameter of incompatible type to a function: " ++ n

-- Tabulka symbolov
type SymTable = (VarTable, FuncTable, VarTable, Bool)   -- Globalne premenne, Funkcie, Lokalne premenne, [Globalny kontext == True, Lokalny kontext == false]

-- ziskanie hodnoty premennej z tabulky symbolov
getSym :: SymTable -> String -> Value
getSym  (gt, ft, lt, gc) name
    | isLocal name = getVar lt name
    | otherwise = getVar gt name
    where
        isLocal n = isVar lt n

-- pridanie nazvu a hodnoty premennej do tabulky symbolov
addSym :: SymTable -> String -> Value -> SymTable
addSym (gt, ft, lt, gc) vName val
    | gc == True && not (isVar gt vName) = (setImplicitSym gt, ft, lt, gc)
    | gc == False && not (isVar lt vName) = (gt, ft, setImplicitSym lt, gc)
    | otherwise = error $ "Multiple declarations of variable: " ++ vName
    where
        setImplicitSym t  = setVar t vName val

-- nastavenie hodnoty premennej do tabulky symbolov
setSym :: SymTable -> String -> Value -> SymTable
setSym (gt, ft, lt, gc) vName val
    | gc == False && (isVar lt vName) = (gt, ft, newVt lt, gc)
    | isVar gt vName = (newVt gt, ft, lt, gc)
    | otherwise = error $ "Cannot assign to non-existing variable: " ++ vName
    where
        newVt t = setVar t vName val

-- vyhodnotenie funkcie s danymi argumentami a uprava tabulky symbolov
getFun :: SymTable -> String -> [Arg] -> IO SymTable
getFun st@(gt, ft, lt, gc) n args = do
    getFuncResult st ft n args

-- zistenie, ci existuje funkcia
isFun :: FuncTable -> String -> Bool
isFun [] name = False
isFun (f:ft) name 
    | name == funcName f = True
    | otherwise = isFun ft name

-- nastavenie novej funkcie
setFun :: SymTable -> String -> Type -> [Param] -> Cmd -> SymTable
setFun (gt, ft, lt, gc) n t ps c = (gt, newFt, lt, gc)
    where
        newFt = setFunc ft n t ps c gc
        
-- nastavenie globalneho kontextu
setGCon :: SymTable -> SymTable
setGCon (gt, ft, lt, gc) = (gt, ft, lt, True)

-- nastavenie lokalneho kontextu
setLCon :: SymTable -> SymTable
setLCon (gt, ft, lt, gc) = (gt, ft, lt, False)

-- prepnutie kontextu
switchCon :: SymTable -> SymTable
switchCon (gt, ft, lt, gc) = (gt, ft, lt, not gc)

-- Vyhodnotenie vyrazov
eval :: SymTable -> Expr -> IO (VarTable, Value)
eval ts@(gt,_,_,_) (Const i) = return (gt, i)

eval ts@(gt, ft, lt, gc) (Add e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' = return (gt', ValInt (i1 + i2))
		ev (ValInt i1) (ValDouble i2) gt' = return (gt', ValDouble (fromIntegral i1 + i2))
		ev (ValDouble i1) (ValInt i2) gt' = return (gt', ValDouble (i1 + fromIntegral i2))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', ValDouble (i1 + i2))
		ev (ValString i1) (ValString i2) gt' = return (gt', ValString (i1 ++ i2))
		ev _ _ _ = error "Type missmatch in operator +"

eval ts@(gt, ft, lt, gc) (Sub e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' = return (gt', ValInt (i1 - i2))
		ev (ValInt i1) (ValDouble i2) gt' = return (gt', ValDouble (fromIntegral i1 - i2))
		ev (ValDouble i1) (ValInt i2) gt' = return (gt', ValDouble (i1 - fromIntegral i2))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', ValDouble (i1 - i2))		
		ev _ _ _ = error "Type missmatch in operator -"

eval ts@(gt, ft, lt, gc) (Mult e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' = return (gt', ValInt (i1 * i2))
		ev (ValInt i1) (ValDouble i2) gt' = return (gt', ValDouble (fromIntegral i1 * i2))
		ev (ValDouble i1) (ValInt i2) gt' = return (gt', ValDouble (i1 * fromIntegral i2))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', ValDouble (i1 * i2))
		ev _ _ _ = error "Type missmatch in operator *"

eval ts@(gt, ft, lt, gc) (Div e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' = return (gt', if (i2 == 0) then error "Division by zero!" else ValInt (i1 `quot` i2))							
		ev (ValInt i1) (ValDouble i2) gt' = return (gt', ValDouble (fromIntegral i1 / i2))
		ev (ValDouble i1) (ValInt i2) gt' = return  (gt', ValDouble (i1 / fromIntegral i2))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', ValDouble (i1 / i2))
		ev _ _ _ = error "Type missmatch in operator /"

eval ts@(gt, ft, lt, gc) (Gt e1 e2) = do
   	(gt', evalLeft) <- eval ts e1
	(gt', evalRight) <- eval (gt', ft, lt, gc) e2
	ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' = return (gt', if (i1 > i2) then (ValInt 1) else (ValInt 0))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', if (i1 > i2) then (ValInt 1) else (ValInt 0))
		ev (ValString i1) (ValString i2) gt' = return (gt', if (i1 > i2) then  (ValInt 1) else (ValInt 0))
		ev _ _ _ = error "Type missmatch in operator >"

eval ts@(gt, ft, lt, gc) (GtEq e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' =  return (gt', if (i1 >= i2) then (ValInt 1) else (ValInt 0))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', if (i1 >= i2) then (ValInt 1) else (ValInt 0))
		ev (ValString i1) (ValString i2) gt' = return (gt', if (i1 >= i2) then (ValInt 1) else (ValInt 0))
		ev _ _ _ = error "Type missmatch in operator >="

eval ts@(gt, ft, lt, gc) (Lt e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' =  return (gt', if (i1 < i2) then (ValInt 1) else (ValInt 0))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', if (i1 < i2) then (ValInt 1) else (ValInt 0))
		ev (ValString i1) (ValString i2) gt' = return (gt', if (i1 < i2) then (ValInt 1) else (ValInt 0))
		ev _ _ _ = error "Type missmatch in operator <"

eval ts@(gt, ft, lt, gc) (LtEq e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' =  return (gt', if (i1 <= i2) then (ValInt 1) else (ValInt 0))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', if (i1 <= i2) then (ValInt 1) else (ValInt 0))
		ev (ValString i1) (ValString i2) gt' = return (gt', if (i1 <= i2) then (ValInt 1) else (ValInt 0))
		ev _ _ _ = error "Type missmatch in operator <="

eval ts@(gt, ft, lt, gc) (Eq e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' = return (gt', if (i1 == i2) then (ValInt 1) else (ValInt 0))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', if (i1 == i2) then (ValInt 1) else (ValInt 0))
		ev (ValString i1) (ValString i2) gt' = return (gt', if (i1 == i2) then (ValInt 1) else (ValInt 0))
		ev _ _ _ = error "Type missmatch in operator =="

eval ts@(gt, ft, lt, gc) (Neq e1 e2) = do
    (gt', evalLeft) <- eval ts e1
    (gt', evalRight) <- eval (gt', ft, lt, gc) e2
    ev evalLeft evalRight gt'
	where 
		ev (ValInt i1) (ValInt i2) gt' =  return (gt', if (i1 /= i2) then (ValInt 1) else (ValInt 0))
		ev (ValDouble i1) (ValDouble i2) gt' = return (gt', if (i1 /= i2) then (ValInt 1) else (ValInt 0))
		ev (ValString i1) (ValString i2) gt' = return (gt', if (i1 /= i2) then (ValInt 1) else (ValInt 0))
		ev _ _ _ = error "Type missmatch in operator !="

eval ts@(gt, _, _, _) (Var v) = return (gt, getSym ts v)

eval ts@(gt, ft, lt, gc) (Fun name args) = do
    (gt', ft', lt', gc') <- getFun (gt, ft, lt, gc) name args
    if (isVar lt' "return") then do
	    case (getVar lt' "return", getFuncType ft' name) of
	        (ValInt i, Int) -> return (gt', ValInt i)
	        (ValInt i, Double) -> return (gt', ValDouble $ fromIntegral i)
	        (ValDouble d, Double) -> return (gt', ValDouble d)
	        (ValString s, String) -> return (gt', ValString s)
	        (_,_) -> error $ "Bad type of returned value in function: " ++ name
	else do
		case (getFuncType ft' name) of
			(Int) -> return (gt', ValInt 0)
			(Double) -> return (gt', ValDouble 0.0)
			(String) -> return (gt', ValString "")

-- overenie, ci nazov premennej je jedinecny identifikator
hasVariableOriginalName :: String -> FuncTable -> Bool
hasVariableOriginalName _ [] = True
hasVariableOriginalName name (f:fs)
    | name == funcName f = False
    | otherwise = hasVariableOriginalName name fs

-- Interpret
interpret :: SymTable -> Cmd -> IO (SymTable,Bool)
interpret ts (Empty) = return (ts,False)

interpret ts@(_,ft,_,gc) (VarDefStmt t varName) =
    if(gc == True && (hasVariableOriginalName varName ft) == False)
        then error $ "Identifier \"" ++ varName ++ "\" has been declared already!"
        else
            case t of
            (Int) -> return ((addSym ts varName $ ValInt 0),False)
            (Double) -> return ((addSym ts varName $ ValDouble 0.0),False)
            (String) -> return ((addSym ts varName $ ValString ""),False)

interpret ts@(gt,ft,lt,gc) (VarDefStmtAssign t varName expr) =
    if(gc == True && (hasVariableOriginalName varName ft) == False)
        then error $ "Identifier \"" ++ varName ++ "\" has been declared already!"
        else do
            (gt', v) <- eval ts expr
            case (t, v) of
                (Int,(ValInt i)) -> return ((addSym (gt', ft, lt, gc) varName $ ValInt i),False)
                (Double,(ValInt i)) -> return ((addSym (gt', ft, lt, gc) varName $ ValDouble $ fromIntegral i),False)
                (Double,(ValDouble d)) -> return ((addSym (gt', ft, lt, gc) varName $ ValDouble d),False)
                (String,(ValString s)) -> return ((addSym (gt', ft, lt, gc) varName $ ValString s),False)
                _ -> error $ "Type missmatch in assigment to \"" ++ varName ++ "\"!"
        
interpret ts@(gt, ft, lt, gc) (AssignStmt v e) =  do 
    (gt', evaluated) <- eval ts e 
    return ((setSym (gt', ft, lt, gc) v evaluated),False)

interpret ts@(gt, ft, lt, gc) (Print e) = do 
    (gt', evaluated) <- eval ts e 
    case evaluated of
        (ValInt i) -> putStrLn $ show i
        (ValDouble d) -> putStrLn $ show d
        (ValString s) -> putStrLn s
    return ((gt', ft, lt, gc),False)

interpret ts (Scan var) = do 
    case getSym ts var of         
        (ValInt i) -> do
            readVal <- readLn :: IO Int  
            return ((setSym ts var $ ValInt readVal),False)
        (ValDouble d) -> do
            readVal <- readLn :: IO Double  
            return ((setSym ts var $ ValDouble readVal),False)
        (ValString s) -> do
            readVal <- getLine  
            return ((setSym ts var $ ValString readVal),False)

interpret ts@(gt, ft, lt, gc) (IfStmt cond cmdTrue cmdFalse) = do
    (gt', evaluated) <- eval ts cond 
    case evaluated of
        (ValInt i) -> if i /= 0 
            then do
                interpret (gt', ft, lt, gc) cmdTrue
            else do
                interpret (gt', ft, lt, gc) cmdFalse
        _ -> error "Condition in if statement is not an integer value!"

interpret ts@(gt, ft, lt, gc) (WhileStmt cond cmd) = do
    (gt', evaluated) <- eval ts cond 
    case evaluated of
        (ValInt i) -> if i /= 0
            then do
                (ts',hasReturn) <- interpret (gt', ft, lt, gc) cmd
                if hasReturn
                    then return (ts',True)
                    else interpret ts' $ WhileStmt cond cmd
            else do
                return ((gt', ft, lt, gc),False)
        _ -> error "Condition in while statement is not an integer value!"

interpret ts@(gt, ft, lt, gc) (ReturnStmt e) = do
    (gt', evaluated) <- eval ts e
    return ((addSym (gt', ft, lt, gc) "return" evaluated),False)

interpret ts (Seq []) = return (ts,False)
interpret ts (Seq (c:cs)) = do
    (ts',hasReturn) <- interpret ts c
    case c of
        (ReturnStmt _) -> return (ts',True)
        _ -> if hasReturn
             then return (ts',True)
             else interpret ts' $ Seq cs

interpret ts@(gt,ft,lt,gc) (FuncCall name args) = do
    tmp@(gt',ft',lt',gc') <- getFun ts name args
    return ((gt',ft',lt, gc'),False)

interpret ts (FuncDecl retType funcName params) = return (ts,False)

interpret ts (Func retType "main" params cmd) = 
    if (retType == Int && params == []) then do
            let ts' = setLCon ts
            (tsAft@(_,_,lt,_),_) <- interpret ts' cmd
            if (isVar lt "return") then do
                case (getVar lt "return") of
                    (ValInt i) -> return (tsAft,False)
                    _ -> error "Bad type of returning value from main!"
            else do
                return (tsAft,False)
        else do
            error "Main has bad return type or has some parameters!"

interpret ts (Func retType funcName params cmd) =   
    return (ts,False)

-- priechod AST pre vyhladanie deklaracii a definicii funkcii
preInterpret :: SymTable -> Cmd -> IO SymTable
preInterpret ts (VarDefStmt t varName) = return ts
preInterpret ts (VarDefStmtAssign t varName _) = return ts
preInterpret ts@(_,_,_,gc) (Func retType "main" params cmd) = return $ setFun ts "main" retType params cmd
preInterpret ts@(_,_,_,gc) (FuncDecl retType "main" params) = return $ setFun ts "main" retType params Empty
preInterpret ts@(_,_,_,gc) (Func retType funcName params cmd) = return $ setFun ts funcName retType params cmd
preInterpret ts@(_,_,_,gc) (FuncDecl retType funcName params) = return $ setFun ts funcName retType params Empty
preInterpret ts (Seq []) = return ts
preInterpret ts (Seq (c:cs)) = do
    ts' <- preInterpret ts c
    preInterpret ts' $ Seq cs
preInterpret ts _ = error "Only declaration or definition can be in global context!"

-- overenie, ci deklaracia globalnych premennych predchadza deklaracii a definicii funkcii
sectionsTest :: Cmd -> Bool -> Bool
sectionsTest (Seq []) _ = True
sectionsTest (Seq (c:cs)) b = case(c) of
    (VarDefStmt _ _) -> if(b)
                        then sectionsTest (Seq cs) True
                        else False
    (VarDefStmtAssign _ _ _) -> if(b)
                        then sectionsTest (Seq cs) True
                        else False
    _ -> sectionsTest (Seq cs) False

-- overenie, ci sa dany retazec nachadza v poli retazcov
isInList :: String -> [String] -> Bool
isInList _ [] = False
isInList name (l:ls)
    | name == l = True
    | otherwise = isInList name ls

-- overenie, ci sa vo vyraze nenachaza nedeklarovana funkcia
exprDeclDefTest :: Expr -> [String] -> Bool
exprDeclDefTest e lt = case (e) of
    (Fun name args) -> ((isInList name lt) && (argsDeclDefTest args lt))
    (Add e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (Sub e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (Mult e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (Div e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (Gt e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (GtEq e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (Lt e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (LtEq e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (Eq e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))
    (Neq e1 e2) -> ((exprDeclDefTest e1 lt) && (exprDeclDefTest e2 lt))

    _ -> True

-- overenie, ci sa v argumentoch funkcie nenachaza nedeklarovana funkcia
argsDeclDefTest :: [Arg] -> [String] -> Bool
argsDeclDefTest [] _ = True
argsDeclDefTest ((Arg e):as) lt = if(exprDeclDefTest e lt)
                                    then argsDeclDefTest as lt
                                    else False

-- overenie, ci sa v prikazoch nenachaza nedeklarovana funkcia
funcDeclDefTest :: Cmd -> [String] -> Bool
funcDeclDefTest (Seq []) _ = True
funcDeclDefTest (Seq (c:cs)) lt = case (c) of
    (FuncDecl _ name _) -> funcDeclDefTest (Seq cs) (name:lt)
    (Func _ name _ cmd) -> if(funcDeclDefTest cmd (name:lt))
                            then funcDeclDefTest (Seq cs) (name:lt)
                            else False
    (FuncCall name args) -> if((isInList name lt) && (argsDeclDefTest args lt))
                            then funcDeclDefTest (Seq cs) lt
                            else False
    (IfStmt e cmd1 cmd2) -> if((exprDeclDefTest e lt) && (funcDeclDefTest cmd1 lt) && (funcDeclDefTest cmd2 lt))
                            then funcDeclDefTest (Seq cs) lt
                            else False
    (WhileStmt e cmd) -> if((exprDeclDefTest e lt) && (funcDeclDefTest cmd lt))
                            then funcDeclDefTest (Seq cs) lt
                            else False
    (AssignStmt _ e) -> if(exprDeclDefTest e lt)
                        then funcDeclDefTest (Seq cs) lt
                        else False
    (VarDefStmtAssign _ _ e) -> if(exprDeclDefTest e lt)
                                then funcDeclDefTest (Seq cs) lt
                                else False
    (ReturnStmt e) -> if(exprDeclDefTest e lt)
                        then funcDeclDefTest (Seq cs) lt
                        else False
    (Print e) -> if(exprDeclDefTest e lt)
                    then funcDeclDefTest (Seq cs) lt
                    else False
    _ -> funcDeclDefTest (Seq cs) lt

-- vytvorenie AST
aep = do
    whiteSpace
    ast <- command
    eof
    return ast
    <?> "Aep parsing error"

-- parsovanie vstupneho suboru do AST
parseAep input file =
    case parse aep file input of
        Left e -> error $ show e
        Right ast -> ast 
    
-- main
main = do
    args <- getArgs
    if length args /= 1
    then error "Specify one input file."
    else do
        let fileName = args!!0
        input <- readFile fileName
        let ast = parseAep ("{" ++ input ++ "}") fileName
        --putStrLn $ show ast
        if(sectionsTest ast True)
            then do
                if(funcDeclDefTest ast [])
                    then do
                        (_, ft, _, _) <- preInterpret ([],[],[], True) ast        
                        if (isFun ft "main") then do
                           interpret ([], ft, [], True) ast 
                        else do
                           error "Missing main function!"
                    else do
                        error "Calling undefined or undeclared function!"
            else do
                error "Global variable declaration after function declaration or definition!"

--end interpret.hs
