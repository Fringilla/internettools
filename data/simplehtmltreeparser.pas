{**
  @abstract This unit contains a html/xml -> tree converter

  @author Benito van der Zander (http://www.benibela.de)
}
unit simplehtmltreeparser;

{$mode objfpc} {$H+}

interface

uses
  Classes, SysUtils, simplehtmlparser, bbutils;

type

{ TAttributeMap }

//**@abstract A list of attributes.
//**Currently this is a simple string list, and you can get the values with the values property. (with c++ I would have used map<string, string> but this doesn't exist in Pascal)
TAttributeList = TStringList; //TODO: use a map

//**The type of a tree element. <Open>, text, or </close>
TTreeElementType = (tetOpen, tetClose, tetText, tetComment, tetProcessingInstruction, tetAttributeValue, tetAttributeName);
TTreeElementTypes = set of TTreeElementType;
//**Controls the search for a tree element.@br
//**ignore type: do not check for a matching type, ignore text: do not check for a matching text,
//**case sensitive: do not ignore the case, no descend: only check elements that direct children of the current node
TTreeElementFindOptions = set of (tefoIgnoreType, tefoIgnoreText, tefoCaseSensitive, tefoNoChildren, tefoNoGrandChildren);

TTreeParser = class;
TTreeDocument = class;

{ TTreeElement }

TStringComparisonFunc = function (const a,b: string): boolean of object;

{ TNamespace }

TNamespace = class
  url: string;
  prefix: string;
  constructor create(const aurl: string; aprefix: string);
end;

{ TNamespaceList }

TNamespaceList = class(TFPList)
private
  function getNamespace(const prefix: string): TNamespace;
  function getNamespace(i: integer): TNamespace;
public
  function hasNamespacePrefix(const prefix: string; out ns: TNamespace): boolean;

  procedure freeAll;
  destructor Destroy; override;

  property namespaces[prefix: string]: TNamespace read getNamespace;
  property items[i: integer]: TNamespace read getNamespace;
end;

//**@abstract This class representates an element of the html file
//**It is stored in an unusual  tree representation: All elements form a linked list and the next element is the first children, or if there is none, the next node on the same level, or if there is none, the closing tag of the current parent.@br
//**E.g. a xml file like @code(<foo><bar>x</bar></foo>) is stored as a quadro-linked list:
//**  @longCode(#
//**   /---------------------------------\
//**   |         |  -----------          |                                   link to parent (for faster access, it would work without it)
//**  \|/        | \|/        |          |
//**   '            '
//** <foo> <---> <bar>  <---> x <--->  </bar>  <--->  </foo>                 double linked list of tags (previous link again for faster access, a single linked list would work as well)
//**   .           .                     .               .
//**  /|\         /|\                   /|\             /|\
//**   |           -----------------------               |                   single linked of corresponding node
//**   ---------------------------------------------------
//**  #)
//**There are functions (getNextSibling, getFirstChild, findNext, ...) to access it like a regular tree, but it is easier and faster to work directly with the list.@br
//**Some invariants: (SO: set of opening tags in sequence)@br
//**∀a \in SO: a < a.reverse@br
//**∀a,b \in SO: a < b < a.reverse => a < b.reverse < a.reverse@br
//**@br
//**Attributes should be accessed with the getAttribute or getAttributeTry method. @br
//**But if you are brave or need to modify the attributes, you can access the internal attribute storage with the attributes field.@br
//**All attributes are stored in the same structure as the other elements as quadro-linked list. The names and values are stored in two lists, which are connected with the connecting @code(reverse) field.@br
//**You can use the second getAttributeTry method to get a pointer to value node for a certain name.
//**
//** @code(<foo name1="value1" name2="value2" name3="value3>/>)
//** @longCode(#
//**      /--------------\                                     pointer to first attribute (attributes)
//**      |              |
//**      |      /-->  <foo>  <-----------------------\
//**      |       |             |           |          |       single linked list to parent (parent)
//**      |       |             |           |          |
//**      \-->  name1  <-->  name2  <-->  name3        |       double linked list of attributes (previous and next)
//**             /|\          /|\          /|\         |
//**              |            |            |          |       single linked list of corresponding node/thing (reverse)
//**             \|/          \|/          \|/         |
//**            value1 <-->  value2 <-->  value3       |       (again) double linked list of attributes (previous and next)
//**              |            |            |          |
//**              \------------------------------------/       (again) single linked list to parent
//** #)
TTreeElement = class
//use the fields if you know what you're doing
  typ: TTreeElementType; //**<open, close, text or comment node
  value: string; //**< tag name for open/close nodes, text for text/comment nodes
  attributes: TTreeElement;  //**<nil if there are no attributes
  next: TTreeElement; //**<next element as in the file (first child if there are childs, else next on lowest level), so elements form a linked list
  previous: TTreeElement; //**< previous element (self.next.previous = self)
  parent: TTreeElement;
  document: TTreeElement;
  reverse: TTreeElement; //**<element paired by open/closing, or corresponding attributes
  namespace: TNamespace; //**< Currently local namespace prefix. Might be changed to a pointer to a namespace map in future. (so use getNamespacePrefix and getNamespaceURL instead)

  offset: longint; //**<count of characters in the document before this element (so document_pchar + offset begins with value)

//otherwise use the functions
  //procedure deleteNext(); //**<delete the next node (you have to delete the reverse tag manually)
  procedure deleteAll(); //**<deletes the tree
  procedure changeEncoding(from,toe: TEncoding; substituteEntities: boolean; trimText: boolean); //**<converts the tree encoding from encoding from to toe, and substitutes entities (e.g &auml;)


  //Complex search functions.
  //**Returns the element with the given type and text which occurs before sequenceEnd.@br
  //**This function is nil-safe, so if you call TTreeElement(nil).findNext(...) it will return nil
  function findNext(withTyp: TTreeElementType; withText:string; findOptions: TTreeElementFindOptions=[]; sequenceEnd: TTreeElement = nil):TTreeElement;
  //**Find a matching direct child (equivalent to findNext with certain parameters, but easier to use)@br
  //**A direct child of X is a node Y with Y.parent = X. @br
  //**The options tefoNoChildren, tefoNoGrandChildren have of course no effect. (former is set to false, latter to true)
  function findChild(withTyp: TTreeElementType; withText:string; findOptions: TTreeElementFindOptions=[]): TTreeElement;

  function deepNodeText(separator: string=''):string; //**< concatenates the text of all (including indirect) text children
  function outerXML(insertLineBreaks: boolean = false):string;
  function innerXML(insertLineBreaks: boolean = false):string;

  function getValue(): string; //**< get the value of this element
  function getValueTry(out valueout:string): boolean; //**< get the value of this element if the element exists
  function hasAttribute(const a: string; const cmpFunction: TStringComparisonFunc = nil): boolean; //**< returns if an attribute with that name exists. cmpFunction controls is used to compare the attribute name the searched string. (can be used to switch between case/in/sensitive)
  function getAttribute(const a: string; const cmpFunction: TStringComparisonFunc = nil):string; //**< get the value of an attribute of this element or '' if this attribute doesn't exist cmpFunction controls is used to compare the attribute name the searched string. (can be used to switch between case/in/sensitive)
  function getAttribute(const a: string; const def: string; const cmpFunction: TStringComparisonFunc = nil):string; //**< get the value of an attribute of this element or '' if this attribute doesn't exist cmpFunction controls is used to compare the attribute name the searched string. (can be used to switch between case/in/sensitive)
  function getAttributeTry(const a: string; out valueout: string; const cmpFunction: TStringComparisonFunc = nil):boolean; //**< get the value of an attribute of this element and returns false if it doesn't exist cmpFunction controls is used to compare the attribute name the searched string. (can be used to switch between case/in/sensitive)
  function getAttributeTry(a: string; out valueout: TTreeElement; cmpFunction: TStringComparisonFunc = nil):boolean; //**< get the value of an attribute of this element and returns false if it doesn't exist cmpFunction controls is used to compare the attribute name the searched string. (can be used to switch between case/in/sensitive)
  function getAttributeCount(): integer;

  function getNextSibling(): TTreeElement; //**< Get the next element on the same level or nil if there is none
  function getFirstChild(): TTreeElement; //**< Get the first child, or nil if there is none
  function getParent(): TTreeElement; //**< Searchs the parent, notice that this is a slow function (neither the parent nor previous elements are stored in the tree, so it has to search the last sibling)
  function getPrevious(): TTreeElement; //**< Searchs the previous, notice that this is a slow function (neither the parent nor previous elements are stored in the tree, so it has to search the last sibling)
  function getRoot(): TTreeElement;    //**< Returns the highest element node ancestor (not the document root, that is returned by getDocument)
  function getDocument(): TTreeDocument; //**< Returns the document node containing this node

  function getNodeName(): string;        //**< Returns the name as namespaceprefix:name if a namespace exists, or name otherwise. Only attributes, elements and PIs have names.
  function getNamespacePrefix(): string; //**< Returns the namespace prefix. (i.e. 'a' for 'a:b', '' for 'b')
  function getNamespaceURL(): string;    //**< Returns the namespace url. (very slow, it searches the parents for a matching xmlns attribute) cmpFunction controls is used to compare the xmlns: attribute name the searched string. (can be used to switch between case/in/sensitive)
  function getNamespaceURL(prefixOverride: string; cmpFunction: TStringComparisonFunc = nil): string; //**< Returns the url of a namespace prefix, defined in this element or one of his parents cmpFunction controls is used to compare the xmlns: attribute name the searched string. (can be used to switch between case/in/sensitive)

  property defaultProperty[name: string]: string read getAttribute; default;

  function isDeepEqual(cmpTo: TTreeElement; ignoredTypes: TTreeElementTypes = [tetComment, tetProcessingInstruction]; cmpFunction: TStringComparisonFunc = nil): boolean;

  procedure insert(el: TTreeElement); //**< inserts el after the current element (does only change next+previous, not reverse+parent)
  procedure insertSurrounding(before, after: TTreeElement); //**< Surrounds self by before and after, i.e. inserts "before" directly before the element and "after" directly after its closing tag (slow)
  procedure insertSurrounding(basetag: TTreeElement); //**< inserts basetag before the current tag, and creates a matching closing tag after the closing tag of self (slow)

  function addAttribute(aname, avalue: string): TTreeElement; //adds a single attribute. Returns the element of the last inserted attribute. (runs in O(|attributes|) => do not use for multiple attributes)
  function addAttributes(const props: array of THTMLProperty): TTreeElement; //adds an array of properties to the attributes. Returns the element of the last inserted attribute.
  procedure addChild(child: TTreeElement);

  procedure removeElementFromDoubleLinkedList; //removes the element from the double linked list (only updates previous/next)
  function deleteElementFromDoubleLinkedList: TTreeElement; //removes the element from the double linked list (only updates previous/next), frees it and returns next  (mostly useful for attribute nodes)

  function clone: TTreeElement;
protected
  function cloneShallow: TTreeElement;

  procedure removeAndFreeNext(); //**< removes the next element (the one following self). (ATTENTION: looks like there is a memory leak for opened elements)
  procedure removeElementKeepChildren; //**< removes/frees the current element, but keeps the children (i.e. removes self and possible self.reverse. Will not remove the opening tag, if called on a closing tag)


public
  function toString(): string; reintroduce; //**< converts the element to a string (not recursive)

  constructor create();
  constructor create(atyp: TTreeElementType; avalue: string = '');
  destructor destroy();override;
  procedure initialized; virtual; //**<is called after an element is read, before the next one is read (therefore all fields are valid except next (and reverse for opening tags))

  function caseInsensitiveCompare(const a,b: string): boolean; //**< returns true if a=b case insensitive. Can be passed to getAttribute
  function caseSensitiveCompare(const a,b: string): boolean;   //**< returns true if a=b case sensitive. Can be passed to getAttribute

  class function compareInDocumentOrder(p1, p2: Pointer): integer;
end;
TTreeElementClass = class of TTreeElement;

{ TTreeDocument }

TTreeDocument = class(TTreeElement)
protected
  FEncoding: TEncoding;
  FBaseURI: string;
  FCreator: TTreeParser;

public
  property baseURI: string read FBaseURI;

  function getCreator: TTreeParser;

  //**Returns the current encoding of the tree. After the parseTree-call it is the detected encoding, but it can be overriden with setEncoding.
  function getEncoding: TEncoding;
  //**Changes the tree encoding
  //**If convertExistingTree is true, the strings of the tree are actually converted, otherwise only the meta encoding information is changed
  //**If convertEntities is true, entities like &ouml; are replaced (which is only possible if the encoding is known)
  procedure setEncoding(new: TEncoding; convertFromOldToNew: Boolean; convertEntities: boolean);

  destructor destroy; override;
end;

ETreeParseException = Exception;
{ TTreeParser }

//**Parsing model used to interpret the document
//**pmStrict: every tag must be closed explicitely (otherwise an exception is raised)
//**pmHtml: accept everything, tries to create the best fitting tree using a heuristic to recover from faulty documents (no exceptions are raised), detect encoding
TParsingModel = (pmStrict, pmHTML);
//**@abstract This parses a html/sgml/xml file to a tree like structure
//**To use it, you have to call @code(parseTree) with a string containing the document. Afterwards you can call @code(getTree) to get the document root node.@br
//**
//**The data structure is like a stream of annotated tokens with back links (so you can traverse it like a tree).@br
//**After tree parsing the tree contains the text as byte strings, without encoding or entity conversions. But in the case of html, the meta/http-equiv encoding is detected
//**and you can call setEncoding to change the tree to the encoding you need. (this will also convert the entities)@br
//**You can change the class used for the elements in the tree with the field treeElementClass.
TTreeParser = class
private
  FAutoDetectHTMLEncoding: boolean;
  FReadProcessingInstructions: boolean;
//  FConvertEntities: boolean;
  FCurrentElement: TTreeElement;
  FTemplateCount: Integer;
  FElementStack: TList;
  FAutoCloseTag: boolean;
  FCurrentFile: string;
  FParsingModel: TParsingModel;
  FTrimText, FReadComments: boolean;
  FTrees: TList;
  FCurrentTree: TTreeDocument;
  FXmlHeaderEncoding: TEncoding;


  function newTreeElement(typ:TTreeElementType; text: pchar; len:longint):TTreeElement;
  function newTreeElement(typ:TTreeElementType; s: string):TTreeElement;
  procedure autoCloseLastTag();

  function enterTag(tagName: pchar; tagNameLen: longint; properties: THTMLProperties):TParsingResult;
  function leaveTag(tagName: pchar; tagNameLen: longint):TParsingResult;
  function readText(text: pchar; textLen: longint):TParsingResult;
  function readComment(text: pchar; textLen: longint):TParsingResult;

private
  FCurrentNamespace: TNamespace;
  FCurrentNamespaces: TNamespaceList;
  FCurrentNamespaceDefinitions: TList;
  FNamespaceGarbage: TNamespaceList;
  function pushNamespace(const url, prefix: string): TNamespace;
  function findNamespace(const prefix: string): TNamespace;

  function htmlTagWeight(s:string): integer;
  function htmlTagAutoClosed(s:string): boolean;
public
  treeElementClass: TTreeElementClass; //**< Class of the tree nodes. You can subclass TTreeElement if you need to store additional data at every node
  globalNamespaces: TNamespaceList;

  constructor Create;
  destructor destroy;override;
  procedure clearTrees;
  //** Creates a new tree from a html document contained in html. @br
  //** The uri parameter is just stored and returned for you by baseURI, not actually used within this class. @br
  //** contentType is used to detect the encoding
  function parseTree(html: string; uri: string = ''; contentType: string = ''): TTreeDocument;
  function parseTreeFromFile(filename: string): TTreeDocument;

  function getLastTree: TTreeDocument; //**< Returns the last created tree

  procedure removeEmptyTextNodes(const whenTrimmed: boolean);
published
  //** Parsing model, see TParsingModel
  property parsingModel: TParsingModel read FParsingModel write FParsingModel;
  //** If this is true (default), white space is removed from text nodes
  property trimText: boolean read FTrimText write FTrimText;
  //** If this is true (default is false) comments are included in the generated tree
  property readComments: boolean read FReadComments write FReadComments;
  //** If this is true (default is false) processing instructions are included in the generated tree
  property readProcessingInstructions: boolean read FReadProcessingInstructions write FReadProcessingInstructions;
  property autoDetectHTMLEncoding: boolean read FAutoDetectHTMLEncoding write fautoDetectHTMLEncoding;
//  property convertEntities: boolean read FConvertEntities write FConvertEntities;
end;


function xmlStrEscape(s: string):string;

const XMLNamespaceUrl_XML = 'http://www.w3.org/XML/1998/namespace';
      XMLNamespaceUrl_XMLNS = 'http://www.w3.org/2000/xmlns/';
var
   XMLNamespace_XMLNS, XMLNamespace_XML: TNamespace;

implementation
uses xquery;

{ TNamespaceList }

function TNamespaceList.getNamespace(const prefix: string): TNamespace;
begin
  hasNamespacePrefix(prefix, result);
end;

function TNamespaceList.getNamespace(i: integer): TNamespace;
begin
  result := TNamespace(inherited get(i));
end;

function TNamespaceList.hasNamespacePrefix(const prefix: string; out ns: TNamespace): boolean;
var
  i: Integer;
begin
  for i := Count - 1 downto 0 do
    if TNamespace(Items[i]).prefix = prefix then begin
      ns := TNamespace(items[i]);
      exit(true);
    end;
  ns := nil;
  exit(false);
end;

procedure TNamespaceList.freeAll;
var
  i: Integer;
begin
  for i := 0 to Count - 1 do items[i].free;
  Clear;
end;

destructor TNamespaceList.Destroy;
begin
  freeAll;
  inherited Destroy;
end;

{ TNamespace }

constructor TNamespace.create(const aurl: string; aprefix: string);
begin
  url := aurl;
  prefix := aprefix;
end;

{ TTreeDocument }

function TTreeDocument.getCreator: TTreeParser;
begin
  result := FCreator;
end;

function TTreeDocument.getEncoding: TEncoding;
begin
  if self = nil then exit(eUnknown);
  result := FEncoding;
end;

procedure TTreeDocument.setEncoding(new: TEncoding; convertFromOldToNew: Boolean; convertEntities: boolean);
begin
  if self = nil then exit;
  if (FEncoding = eUnknown) or not convertFromOldToNew then FEncoding:= new;
  if convertFromOldToNew or convertEntities then changeEncoding(FEncoding, new, convertEntities, FCreator.FTrimText);
  FEncoding := new;
end;

destructor TTreeDocument.destroy;
begin
  inherited destroy;
end;

{ TTreeElement }

{procedure TTreeElement.deleteNext();
var
  temp: TTreeElement;
begin
  if next = nil then exit;
  temp := next;
  next := next.next;
  temp.Free;
end;}

procedure TTreeElement.deleteAll();
begin
  if next <> nil then next.deleteAll();
  next:=nil;
  Free;
end;

procedure TTreeElement.changeEncoding(from, toe: TEncoding; substituteEntities: boolean; trimText: boolean);
  function change(s: string): string;
  begin
    result := strChangeEncoding(s, from, toe);
    if substituteEntities then result := strDecodeHTMLEntities(result, toe, false);
    if trimText then result := trim(result); //retrim because &nbsp; replacements could have introduced new spaces
  end;

var tree: TTreeElement;
  s: String;
  attrib: TTreeElement;
begin
  if (from = eUnknown) or (toe = eUnknown) then exit;
  if (from = toe) and not substituteEntities then exit;
  tree := self;
  while tree <> nil do begin
    case tree.typ of
      tetText, tetProcessingInstruction: tree.value := change(tree.value);
      tetComment: tree.value:=strChangeEncoding(tree.value, from, toe);
      tetOpen, tetClose: begin
        tree.value := change(tree.value);
        attrib := tree.attributes;
        while attrib <> nil do begin
          attrib.value := change(attrib.value);
          assert(attrib.reverse <> nil);
          attrib.reverse.value := change(attrib.reverse.value);
          attrib := attrib.next;
        end;
      end;
      else raise Exception.Create('Unkown tree element: '+tree.outerXML());
    end;
    tree := tree.next;
  end;
end;

function TTreeElement.findNext(withTyp: TTreeElementType; withText: string; findOptions: TTreeElementFindOptions =[]; sequenceEnd: TTreeElement = nil): TTreeElement;
var cur: TTreeElement;
  //splitted: array of string;
begin
  if self = nil then exit(nil);
  {if (tefoSplitSlashes in findOptions) and not (tefoIgnoreType in findOptions) and not (tefoIgnoreText in findOptions) and (withTyp = tetOpen) and (pos('/'.withText) > 0) then begin
    result := findNext(tetOpen, strSplitGet('/', withText), findOptions - [tefoSplitSlashes], sequenceEnd);
    while (result <> nil) and (withText <> '') do
      result := result.findNext(tetOpen, strSplitGet('/', withText), findOptions - [tefoSplitSlashes], result.reverse);
    exit();
  end;}
  if (tefoNoChildren in findOptions) and (self.typ = tetOpen) then cur := self.reverse
  else cur := self.next;
  while (cur <> nil) and (cur <> sequenceEnd) do begin
    if ((cur.typ = withTyp) or (tefoIgnoreType in findOptions)) and
       ((tefoIgnoreText in findOptions) or
           ( (tefoCaseSensitive in findOptions) and (cur.value = withText) ) or
           ( not (tefoCaseSensitive in findOptions) and (striequal(cur.value, withText) ) ) ) then
             exit(cur);
    if (tefoNoGrandChildren in findOptions) and (cur.typ = tetOpen) then cur := cur.reverse
    else cur := cur.next;
  end;
  result := nil;
end;

function TTreeElement.findChild(withTyp: TTreeElementType; withText: string;
  findOptions: TTreeElementFindOptions): TTreeElement;
begin
  result := nil;
  if self = nil then exit;
  if typ <> tetOpen then exit;
  if reverse = nil then exit;
  result:=findNext(withTyp, withText, findOptions + [tefoNoGrandChildren] - [tefoNoChildren], reverse);
end;

function TTreeElement.deepNodeText(separator: string): string;
var cur:TTreeElement;
begin
  result:='';
  if self = nil then exit;
  cur := next;
  while (cur<>nil) and (cur <> reverse) do begin
    if cur.typ = tetText then result:=result+cur.value+separator;
    cur := cur.next;
  end;
  if (result<>'') and (separator<>'') then setlength(result,length(result)-length(separator));
end;

function TTreeElement.outerXML(insertLineBreaks: boolean = false): string;
var i: Integer;
  attrib: TTreeElement;
begin
  if self = nil then exit;
  case typ of
    tetText: result := xmlStrEscape(value);
    tetClose: result := '</'+getNodeName()+'>';
    tetComment: result := '<!--'+value+'-->';
    tetProcessingInstruction: begin
      result := '<?'+value;
      if attributes <> nil then result += ' '+attributes.reverse.value;
      result += '?>';
    end;
    tetOpen: begin
      if (value = '') and (self is TTreeDocument) then exit(innerXML());
      result := '<' + getNodeName();
      attrib := attributes;
      while attrib <> nil do begin
        assert(attrib.reverse <> nil);
        result += ' ';
        if attrib.namespace <> nil then result += attrib.getNamespacePrefix()+':';
        result += attrib.value+'="'+attrib.reverse.value+'"'; //todo fix escaping & < >
        attrib := attrib.next;
      end;

      if next = reverse then begin
        result += '/>';
        if insertLineBreaks then Result+=LineEnding;
        exit();
      end;
      result +='>';
      if insertLineBreaks then Result+=LineEnding;
      result += innerXML(insertLineBreaks);
      result+='</'+value+'>';
      if insertLineBreaks then Result+=LineEnding;
    end;
  end;
end;

function TTreeElement.innerXML(insertLineBreaks: boolean = false): string;
var
  sub: TTreeElement;
begin
  result := '';
  if (self = nil) or (typ <> tetOpen) then exit;
  sub := next;
  while sub <> reverse do begin
    result += sub.outerXML(insertLineBreaks);
    if sub.typ <> tetOpen then sub:=sub.next
    else sub := sub.reverse.next;
  end;
end;

function TTreeElement.getValue(): string;
begin
  if self = nil then exit('');
  result := value;
end;

function TTreeElement.getValueTry(out valueout:string): boolean;
begin
  if self = nil then exit(false);
  valueout := self.value;
  result := true;
end;

function TTreeElement.hasAttribute(const a: string; const cmpFunction: TStringComparisonFunc = nil): boolean;
var temp: TTreeElement;
begin
  exit(getAttributeTry(a, temp, cmpFunction));
end;

function TTreeElement.getAttribute(const a: string; const cmpFunction: TStringComparisonFunc = nil): string;
begin
  if not getAttributeTry(a, result, cmpFunction) then
    result:='';
end;

function TTreeElement.getAttribute(const a: string; const def: string; const cmpFunction: TStringComparisonFunc = nil):string;
begin
  if not getAttributeTry(a, result, cmpFunction) then
    result:=def;
end;

function TTreeElement.getAttributeTry(const a: string; out valueout: string; const cmpFunction: TStringComparisonFunc = nil): boolean;
var temp: TTreeElement;
begin
  result := getAttributeTry(a, temp, cmpFunction);
  if not result then exit;
  valueout := temp.value;
end;

function TTreeElement.getAttributeTry(a: string; out valueout: TTreeElement; cmpFunction: TStringComparisonFunc = nil): boolean;
var
  attrib: TTreeElement;
  checkNamespace: Boolean;
  ns: string;
begin
  result := false;
  if self = nil then exit;
  attrib := attributes;
  checkNamespace := pos(':', a) > 0;
  if checkNamespace then
    ns := strSplitGet(':', a);

  if cmpFunction = nil then cmpFunction:=@caseInsensitiveCompare;

  while attrib <> nil do begin
    if cmpFunction(attrib.value, a) and (not checkNamespace or cmpFunction(ns, attrib.getNamespacePrefix())) then begin
      valueout := attrib.reverse;
      exit(true);
    end;
    attrib := attrib.next;
  end;
end;

function TTreeElement.getAttributeCount: integer;
var
  temp: TTreeElement;
begin
  result := 0;
  temp := attributes;
  while temp <> nil do begin
    result += 1;
    temp := temp.next;
  end;
end;

function TTreeElement.getNextSibling(): TTreeElement;
begin
  case typ of
    tetOpen: result:=reverse.next;
    tetText, tetClose, tetComment, tetProcessingInstruction: result := next;
    else raise Exception.Create('Invalid tree element type');
  end;
  if result.typ = tetClose then exit(nil);
end;

function TTreeElement.getFirstChild(): TTreeElement;
begin
  if typ <> tetOpen then exit(nil);
  if next = reverse then exit(nil);
  exit(next);
end;

function TTreeElement.getParent(): TTreeElement;
begin
  if (self = nil) then exit(nil);
  exit(parent);
end;

function TTreeElement.getPrevious: TTreeElement;
begin
  if self = nil then exit;
  result := previous
end;

function TTreeElement.getRoot: TTreeElement;
begin
  result := document;
  if (result = nil) or (result.value <> '') then exit;
  exit(result.findChild(tetOpen,'',[tefoIgnoreText]));
end;

function TTreeElement.getDocument: TTreeDocument;
begin
  result := document as TTreeDocument;
end;

function TTreeElement.getNodeName: string;
begin
  case typ of
    tetOpen, tetAttributeName, tetClose: begin
      if (namespace = nil) or (namespace.prefix = '') then exit(value);
      exit(getNamespacePrefix() + ':' + value);
    end;
    tetAttributeValue: result := reverse.getNodeName();
    else result := '';
  end;
end;

function TTreeElement.getNamespacePrefix: string;
begin
  if namespace = nil then exit('');
  result := namespace.prefix;
end;

function TTreeElement.getNamespaceURL(): string;
begin
  if namespace = nil then exit('');
  result := namespace.url;
end;

function TTreeElement.getNamespaceURL(prefixOverride: string; cmpFunction: TStringComparisonFunc = nil): string;
var
  n: TTreeElement;
  attrib: String;
begin
  if (namespace <> nil) and (namespace.prefix = prefixOverride) then exit(namespace.url) ;
  if prefixOverride <> '' then prefixOverride:=':'+prefixOverride;
  attrib := 'xmlns' + prefixOverride;
  n := self;
  while n <> nil do begin
    if n.getAttributeTry(attrib, result, cmpFunction) then
      exit;
    n := n.getParent();
  end;
  exit('');
end;

function TTreeElement.isDeepEqual(cmpTo: TTreeElement; ignoredTypes: TTreeElementTypes; cmpFunction: TStringComparisonFunc): boolean;
var
  attrib: TTreeElement;
  temp1, temp2: TTreeElement;
begin
  //this follows the XPath deep-equal function
  result := false;
  if typ <> cmpTo.typ then exit();
  if not cmpFunction(value, cmpTo.value) then exit;
  case typ of
    tetAttributeName, tetAttributeValue: if not cmpFunction(reverse.value, cmpTo.reverse.value) then exit;
    tetProcessingInstruction: if getAttribute('') <> cmpTo.getAttribute('') then exit;
    tetOpen: begin
      if (next = reverse) <> (cmpTo.next = cmpTo.reverse) then exit;
      if getAttributeCount <> cmpTo.getAttributeCount then exit;
      attrib := attributes;
      while attrib <> nil do begin
        if not cmpTo.getAttributeTry(attrib.value, temp1, cmpFunction) then exit;
        if not cmpFunction(temp1.value, attrib.reverse.value) then exit;
        attrib := attrib.next;
      end;

      temp1 := next; temp2 := cmpTo.next;
      while (temp1 <> nil) and (temp1.typ in ignoredTypes) do temp1 := temp1.getNextSibling();
      while (temp2 <> nil) and (temp2.typ in ignoredTypes) do temp2 := temp2.getNextSibling();
      while (temp1 <> nil) and (temp2 <> nil) do begin
        if not temp1.isDeepEqual(temp2, ignoredTypes, cmpFunction) then exit;
        temp1 := temp1.getNextSibling();
        temp2 := temp2.getNextSibling();
        while (temp1 <> nil) and (temp1.typ in ignoredTypes) do temp1 := temp1.getNextSibling();
        while (temp2 <> nil) and (temp2.typ in ignoredTypes) do temp2 := temp2.getNextSibling();
      end;
    end;
    tetComment, tetText, tetClose: ;
    else raise ETreeParseException.Create('Invalid node type');
  end;
  result := true;
end;

procedure TTreeElement.insert(el: TTreeElement);
begin
  // self  self.next  => self el self.next
  if self = nil then exit;
  el.next := self.next;
  self.next := el;
  el.offset := offset;
  el.previous:=self;
  if el.next <> nil then el.next.previous := el;
end;

procedure TTreeElement.insertSurrounding(before, after: TTreeElement);
var surroundee, prev: TTreeElement;
  el: TTreeElement;
begin
  if self = nil then exit;
  if self.typ = tetClose then surroundee := reverse
  else surroundee := self;
  prev := surroundee.getPrevious();
  if prev = nil then exit;

  prev.insert(before);

  if surroundee.typ = tetOpen then surroundee.reverse.insert(after)
  else surroundee.insert(after);

  before.reverse := after;
  after.reverse := before;

  if (before.typ = tetOpen) and (before.reverse = after) then begin
    prev := surroundee.getParent();
    el := surroundee;
    while (el <> nil) and (el.parent = prev) do begin
      el.parent := before;
      el := el.getNextSibling();
    end;
  end;
end;

procedure TTreeElement.insertSurrounding(basetag: TTreeElement);
var closing: TTreeElement;
begin
  if basetag.typ <> tetOpen then raise Exception.Create('Need an opening tag to surround another tag');
  closing := TTreeElement(basetag.ClassType.Create);
  closing.typ := tetClose;
  closing.value := basetag.value;
  insertSurrounding(basetag, closing);
end;

function TTreeElement.addAttribute(aname, avalue: string): TTreeElement;
var temp: THTMLProperties;
begin
  SetLength(temp, 1);
  temp[0].name:=pchar(aname);
  temp[0].nameLen:=length(aname);
  temp[0].value:=pchar(avalue);
  temp[0].valueLen:=length(avalue);
  addAttributes(temp);
end;

function TTreeElement.addAttributes(const props: array of THTMLProperty): TTreeElement;
var
  prev: TTreeElement;
  attrib: TTreeElement;
  i: Integer;
  newoffset: Integer;
begin
  if length(props) = 0 then exit(nil);

  newoffset := offset + 1;

  prev := attributes;
  if prev <> nil then begin
    while prev.next <> nil do
      prev := prev.next;
    newoffset := prev.offset + 1;
  end;


  for i := 0 to high(props) do begin
    attrib := TTreeElement.create(tetAttributeName, strFromPchar(props[i].name, props[i].nameLen));
    attrib.parent := self;
    attrib.document := document;
    if prev <> nil then prev.next := attrib
    else attributes := attrib;
    attrib.previous := prev;
    attrib.offset:=newoffset; //offset hack to sort attributes after their parent elements in result sequence


    attrib.reverse := TTreeElement.create(tetAttributeValue, strFromPchar(props[i].value, props[i].valueLen));
    attrib.reverse.parent := self;
    attrib.reverse.document := document;
    attrib.reverse.reverse := attrib;
    if prev <> nil then begin
      prev.reverse.next := attrib.reverse ;
      attrib.reverse.previous := prev.reverse;
    end;
    attrib.reverse.offset:=newoffset;

    newoffset+=1;
    prev := attrib;
  end;

  exit(attrib);


end;

procedure TTreeElement.addChild(child: TTreeElement);
var
  oldprev: TTreeElement;
begin
  child.parent := self;
  oldprev := reverse.previous;
  oldprev.next := child;
  child.previous := oldprev;
  if child.reverse = nil then begin
    reverse.previous := child;
    child.next := reverse;
  end else begin
    reverse.previous := child.reverse;
    child.reverse.next := reverse;
  end;
end;

procedure TTreeElement.removeElementFromDoubleLinkedList;
begin
  if previous <> nil then previous.next := next;
  if next <> nil then next.previous := nil;
end;

function TTreeElement.deleteElementFromDoubleLinkedList: TTreeElement;
begin
  result := next;
  removeElementFromDoubleLinkedList;
  free;
end;


function TTreeElement.cloneShallow: TTreeElement;
var
  newattribtail: TTreeElement;
  attrib: TTreeElement;
begin
  result := TTreeElement.create();
  result.typ := typ;
  result.value := value;
  result.attributes := attributes;
  result.next := nil;
  result.previous := nil;
  result.parent := nil;
  result.reverse := nil;
  result.namespace := namespace;
  result.offset := offset;

  if typ = tetAttributeName then begin
    result.reverse := reverse.cloneShallow;
    result.reverse.next := nil;
    result.reverse.previous := nil;
  end;

  if attributes <> nil then begin
    result.attributes := attributes.cloneShallow;
    newattribtail := result.attributes;
    attrib := attributes.next;
    while attrib <> nil do begin
      newattribtail.next := attrib.cloneShallow;
      newattribtail.reverse.next := newattribtail.next.reverse;
      newattribtail.next.previous := newattribtail;
      newattribtail.next.reverse.previous := newattribtail.reverse;

      attrib := attrib.next;
      newattribtail := newattribtail.next;
    end;
  end;
end;

function TTreeElement.clone: TTreeElement;
var
  kid, attrib: TTreeElement;
  newattribhead, newattribtailend: TTreeElement;
begin
  case typ of
    tetOpen: begin
      result := cloneShallow;
      result.reverse := reverse.cloneShallow;
      result.reverse.reverse := result;
      result.next := result.reverse;
      result.reverse.previous := result;

      kid := getFirstChild();
      while kid <> nil do begin
        result.addChild(kid.clone);
        kid := kid.getNextSibling();
      end;
    end;
    tetText, tetComment, tetProcessingInstruction, tetAttributeName: result := cloneShallow;
    tetAttributeValue: result := reverse.cloneShallow;
    tetClose: raise ETreeParseException.Create('Cannot clone closing tag');
    else raise ETreeParseException.Create('Unknown tag');
  end;
  result.previous := nil;
  if result.reverse <> nil then Result.reverse.next := nil
  else result.next := next;
end;

procedure TTreeElement.removeAndFreeNext();
var
  toFree: TTreeElement;
  temp: TTreeElement;
begin
  if (self = nil) or (next = nil) then exit;
  toFree := next;
  if toFree.typ = tetOpen then begin
    temp := toFree.next;
    next := toFree.reverse.next;
    while temp <> toFree.next do begin //remove all between ]toFree, toFree.reverse] = ]toFree, toFree.next[
      temp.free;
      temp := temp.next;
    end;
  end else if toFree.typ = tetClose then
    raise Exception.Create('Cannot remove single closing tag')
  else
    next := toFree.next;
  next.previous := self;
  tofree.free;
end;

procedure TTreeElement.removeElementKeepChildren;
var
  temp: TTreeElement;
begin
  if previous = nil then raise Exception.Create('Cannot remove first tag');
  previous.next := next;
  next.previous := previous;
  if typ = tetOpen then begin
    temp := next;
    while temp <> reverse do begin
      if temp.parent = self then temp.parent := parent;
      temp := temp.getNextSibling();
    end;
    reverse.removeElementKeepChildren;
  end;
  free;
end;

function TTreeElement.caseInsensitiveCompare(const a, b: string): boolean;
begin
  result := striEqual(a, b);
end;

function TTreeElement.caseSensitiveCompare(const a, b: string): boolean;
begin
  result := a = b;
end;

function TTreeElement.toString(): string;
var
  i: Integer;
  attrib: TTreeElement;
begin
  if self = nil then exit('');
  case typ of
    tetText: exit(value);
    tetClose: exit('</'+value+'>');
    tetOpen: begin
      if (value = '') and (self is TTreeDocument) then exit(innerXML());
      result := '<'+value;
      attrib := attributes;
      while attrib <> nil do begin
        result += ' '+attrib.value + '="'+attrib.reverse.value+'"';
        attrib := attrib.next;
      end;
      result+='>';
    end;
    tetComment: exit('<!--'+value+'-->');
    else exit('??');
  end;
end;

constructor TTreeElement.create();
begin
end;

constructor TTreeElement.create(atyp: TTreeElementType; avalue: string);
begin
  self.typ := atyp;
  self.value := avalue;
end;

destructor TTreeElement.destroy();
begin
  if attributes <> nil then begin
    if attributes.reverse <> nil then attributes.reverse.deleteAll();
    attributes.deleteAll();
  end;
  inherited destroy();
end;

procedure TTreeElement.initialized;
begin

end;

class function TTreeElement.compareInDocumentOrder(p1, p2: Pointer): integer;
begin
  if TTreeElement(p1).offset < TTreeElement(p2).offset then exit(-1)
  else if TTreeElement(p1).offset > TTreeElement(p2).offset then exit(1)
  else if p1 = p2 then exit(0)
  else raise Exception.Create('invalid comparison');
end;



{ THTMLTreeParser }

function TTreeParser.newTreeElement(typ:TTreeElementType; text: pchar; len: longint): TTreeElement;
begin
  result := newTreeElement(typ, strFromPchar(text, len));
  result.offset:=longint(text - @FCurrentFile[1]);
end;

function TTreeParser.newTreeElement(typ: TTreeElementType; s: string
  ): TTreeElement;
begin
  result:=treeElementClass.Create;
  result.typ := typ;
  result.value := s;
  result.document := FCurrentTree;
  FTemplateCount+=1;

  FCurrentElement.next := result;
  result.previous := FCurrentElement;
  FCurrentElement := result;

  if typ <> tetClose then result.parent := TTreeElement(FElementStack.Last)
  else result.parent := TTreeElement(FElementStack.Last).getParent();
  //FCurrentElement.id:=FTemplateCount;
end;

procedure TTreeParser.autoCloseLastTag();
var
  last: TTreeElement;
  new: TTreeElement;
begin
  last := TTreeElement(FElementStack.Last);
  Assert(last<>nil);
  if last.typ = tetOpen then begin
    new := newTreeElement(tetClose, last.value);
    //new := treeElementClass.create();
    //new.typ:=tetClose;
    //new.value:=last.value;
    new.offset:=last.offset;
    //new.next:=last.next;
    //last.next:=new;
    last.reverse:=new; new.reverse:=last;
  end;
  FElementStack.Delete(FElementStack.Count-1);
  FAutoCloseTag:=false;
end;

function TTreeParser.enterTag(tagName: pchar; tagNameLen: longint;
  properties: THTMLProperties): TParsingResult;
var
  new,temp: TTreeElement;
  i: Integer;
  j: Integer;
  enc: String;
  first,last: PChar;
  attrib: TTreeElement;
begin
  result:=prContinue;

  if tagName^ = '?' then begin //processing instruction
    if strlEqual(tagName, '?xml', tagNameLen) then begin
      enc := lowercase(getProperty('encoding', properties));
      if enc = 'utf-8' then FXmlHeaderEncoding:=eUTF8
      else if (enc = 'windows-1252') or (enc = 'iso-8859-1') or (enc = 'iso-8859-15') or (enc = 'latin1') then
        FXmlHeaderEncoding:=eWindows1252;
      exit;
    end;
    if not FReadProcessingInstructions then exit;
    new := newTreeElement(tetProcessingInstruction, tagName + 1, tagNameLen - 1);
    if length(properties)>0 then begin
      first := properties[0].name;
      first-=1;
      while first^ in [' ',#9] do first-=1;
      first+=2;
      last := properties[high(properties)].value + properties[high(properties)].valueLen;
      while ((last+1)^ <> #0) and ((last^ <> '?') or ((last+1)^ <> '>'))  do last+=1;

      new.addAttribute('', strFromPchar(first, last-first));
      new.addAttributes(properties);
    end;
    new.initialized;
    exit;
  end;

  if FAutoCloseTag then autoCloseLastTag();
  if (FParsingModel = pmHTML) then begin
    //table hack (don't allow two open td/tr unless separated by tr/table)
    if strliEqual(tagName,'td',tagNameLen) then begin
      for i:=FElementStack.Count-1 downto 0 do begin
        temp :=TTreeElement(FElementStack[i]);
        if not (temp.typ in  [tetOpen, tetClose]) then continue;
        if (temp.value<>'tr') and (temp.value<>'td') and (temp.value<>'table') then continue;
        if (temp.typ = tetClose) then break;
        if (temp.typ = tetOpen) and (temp.value='td') then begin
          for j:=FElementStack.count-1 downto i do
            autoCloseLastTag();
          break;
        end;
        (*if (temp.typ = [tetOpen]) and ((temp.value='tr') or (temp.value='table')) then *)break;
      end;
    end else if strliEqual(tagName,'tr',tagNameLen) then begin
      for i:=FElementStack.Count-1 downto 0 do begin
        temp :=TTreeElement(FElementStack[i]);
        if not (temp.typ in  [tetOpen, tetClose]) then continue;
        if (temp.value<>'tr') and (temp.value<>'td') and (temp.value<>'table') then continue;
        if (temp.typ = tetClose) and ((temp.value='tr') or (temp.value='table')) then break;
        if (temp.typ = tetOpen) and (temp.value='tr') then begin
          for j:=FElementStack.count-1 downto i do
            autoCloseLastTag();
          break;
        end;
        if (temp.typ = tetOpen) and (temp.value='table') then break;
      end;
    end;
  end;
  new := newTreeElement(tetOpen, tagName, tagNameLen);
  if (FParsingModel = pmHTML) then //normal auto close
    FAutoCloseTag:=htmlTagAutoClosed(new.value);

  FElementStack.Add(new);
  if length(properties)>0 then begin
    new.addAttributes(properties);
    attrib := new.attributes;
    while attrib <> nil do begin
      if strBeginsWith(attrib.value, 'xmlns') then begin
        if attrib.value = 'xmlns' then
           pushNamespace(attrib.reverse.value, '')
         else if strBeginsWith(attrib.value, 'xmlns:') then begin
           attrib.value:=strCopyFrom(attrib.value, 7);
           pushNamespace(attrib.reverse.value, attrib.value);
           attrib.namespace := XMLNamespace_XMLNS;
         end;
      end else if pos(':', attrib.value) > 0 then
        attrib.namespace := findNamespace(strSplitGet(':', attrib.value));
      attrib := attrib.next;
    end;
  end;
  if (pos(':', new.value) > 0) then
    new.namespace := findNamespace(strSplitGet(':', new.value))
   else
    new.namespace := FCurrentNamespace;;

  new.initialized;
end;

function TTreeParser.leaveTag(tagName: pchar; tagNameLen: longint): TParsingResult;
var
  new,last,temp: TTreeElement;
  match: longint;
  i: Integer;
  weight: LongInt;
  parenDelta: integer;
  name: String;
  removedCurrentNamespace: Boolean;
begin
  result:=prContinue;

  last := TTreeElement(FElementStack.Last);
  if (FParsingModel = pmStrict) and (last = nil) then
    raise ETreeParseException.create('The tag <'+strFromPchar(tagName,tagNameLen)+'> was closed, but none was open');

  if last = nil then exit;

  if FAutoCloseTag and (not strliequal(tagName, last.value, tagNameLen)) then autoCloseLastTag();
  FAutoCloseTag:=false;

  new := nil;
  if (strliequal(tagName, last.getNodeName, tagNameLen)) then begin
    new := newTreeElement(tetClose, tagName, tagNameLen);
    new.reverse := last; last.reverse := new;
    FElementStack.Delete(FElementStack.Count-1);
    new.initialized;
  end else if FParsingModel = pmStrict then
    raise ETreeParseException.Create('The tag <'+strFromPchar(tagName,tagNameLen)+'> was closed, but the latest opened was <'+last.value+'>  (url: '+FCurrentTree.FBaseURI+')')
  else if FParsingModel = pmHTML then begin
    //try to auto detect unclosed tags
    match:=-1;
    for i:=FElementStack.Count-1 downto 0 do
      if strliequal(tagName, TTreeElement(FElementStack[i]).value, tagNameLen) then begin
        match:=i;
        break;
      end;
    if match > -1 then begin
      //there are unclosed tags, but a tag opening the currently closed exist, close all in between
      weight := htmlTagWeight(strFromPchar(tagName, tagNameLen));
      for i:=match+1 to FElementStack.Count-1 do
        if htmlTagWeight(TTreeElement(FElementStack[i]).value) > weight then
            exit;
      for i:=match+1 to FElementStack.Count-1 do
        autoCloseLastTag();
      new := newTreeElement(tetClose, tagName, tagNameLen);
      last := TTreeElement(FElementStack[match]);
      last.reverse := new; new.reverse := last;
      FElementStack.Count:=match;
      new.initialized;
    end;

    name := strFromPchar(tagName, tagNameLen);
    if htmlTagAutoClosed(name) then begin
      parenDelta := 0;
      last := FCurrentElement;
      while last <> nil do begin
        if last.typ = tetClose then parenDelta -= 1
        else if (last.typ = tetOpen) then begin
          parenDelta+=1;
          if (last.value = name) then begin
            if (last.reverse <> last.next) or (parenDelta <> 0) then break; //do not allow nested auto closed elements (reasonable?)
            //remove old closing tag, and insert new one at the end
            new := newTreeElement(tetClose, tagName, tagNameLen);
            last.reverse.removeElementKeepChildren;
            last.reverse := new; new.reverse := last;

            new.parent := last.parent;

            //update parents
            temp := last.getFirstChild();
            while (temp <> nil) and (last <> new) do begin
              if temp.parent = last.parent then temp.parent := last;
              temp := temp.getNextSibling();
            end;
            break;
          end;
        end;
        last := last.previous;
      end;
    end;

    //if no opening tag can be found the closing tag is ignored (not contained in tree)
  end;

  if new <> nil then begin
    if pos(':', new.value) > 0 then new.namespace := findNamespace(strSplitGet(':', new.value))
    else new.namespace := FCurrentNamespace;
    removedCurrentNamespace := false;
    while (FCurrentNamespaceDefinitions.Count > 0) and (FCurrentNamespaceDefinitions[FCurrentNamespaceDefinitions.Count-1] = pointer(new.reverse)) do begin
      if FCurrentNamespaces.items[FCurrentNamespaces.Count - 1].prefix = '' then
        removedCurrentNamespace := true;
      FCurrentNamespaceDefinitions.Delete(FCurrentNamespaceDefinitions.Count-1);
      FCurrentNamespaces.Delete(FCurrentNamespaces.Count-1);
    end;
    if removedCurrentNamespace then
      FCurrentNamespace := findNamespace('');
  end;
end;

function TTreeParser.readText(text: pchar; textLen: longint): TParsingResult;
begin
  result:=prContinue;

  if (FParsingModel = pmStrict) and (FElementStack.Count < 2) then begin
    strlTrimLeft(text, textLen);
    if textLen = 0 then exit;
    if strBeginsWith(text, #239#187#191) or strBeginsWith(text,#254#255) or strBeginsWith(text, #255#254) or
       strBeginsWith(text, #43#47#118) then raise Exception.Create('xml ' + FCurrentTree.FBaseURI + ' starts with unicode BOM. That is not supported');
    raise ETreeParseException.Create('Data not allowed at root level: '+strFromPchar(text,textLen));
  end;

  if FAutoCloseTag then
    autoCloseLastTag();

  if FTrimText then
    strlTrim(text, textLen, [' ',#0,#9,#10,#13]);

  if textLen = 0 then
    exit;

  newTreeElement(tetText, text, textLen).initialized;
end;

function TTreeParser.readComment(text: pchar; textLen: longint): TParsingResult;
begin
  result:=prContinue;
  if not FReadComments then
    exit;
  if textLen <= 0 then
    exit;
  newTreeElement(tetComment, text, textLen).initialized;
end;

function TTreeParser.pushNamespace(const url, prefix: string): TNamespace;
var
  ns: TNamespace;
begin
  ns := TNamespace.Create(url, prefix);
  FCurrentNamespaces.Add(ns);
  FNamespaceGarbage.Add(ns);
  FCurrentNamespaceDefinitions.Add(FCurrentElement);
  if prefix = '' then FCurrentNamespace := ns;
  result := ns;
end;

function TTreeParser.findNamespace(const prefix: string): TNamespace;
var
  i: Integer;
begin
  result := nil;
  if FCurrentNamespaces.hasNamespacePrefix(prefix, result) then exit;
  if globalNamespaces.hasNamespacePrefix(prefix, result) then exit;
  case prefix of
    'xml': result := XMLNamespace_XML;
    'xmlns': result := XMLNamespace_XMLNS;
    '': result := FCurrentNamespace;
    else if parsingModel = pmStrict then raise ETreeParseException.Create('Unknown namespace: '+prefix);
  end;
end;

function TTreeParser.htmlTagWeight(s: string): integer;
begin
  result := 0;
  //feather tags "b br em hr i p"
  if striequal(s, 'b') or striequal(s, 'em') or
     striequal(s, 'em') or striequal(s, 'p') or striequal(s, 'i') or
     striequal(s, 'o') then exit(-1);

  //middle weight  a 'applet'     'area'    'caption'    'center'     'form'    'h1'    'h2'    'h3'    'h4'    'h5'    'h6'    'iframe'    'input'    'span'
  if striequal(s, 'span') then exit(1);

  //heavy weight 'bod y' 'code' 'dd' 'dl' 'div' 'dt' 'fieldset' 'head' 'html' 'li' 'menu'  'table' 'td' 'tr' 'ul'
  if striequal(s, 'code') or  striequal(s,'fieldset') or striequal(s,'head') or striequal(s,'menu') then exit(2);
  if striequal(s, 'td') or striequal(s, 'ul') or striequal(s, 'ol') or striequal(s, 'dd') or striequal(s, 'dt') then exit(3);
  if striequal(s, 'tr') or striequal(s, 'li') or striequal(s, 'dl') then exit(4);
  if striequal(s, 'body') or striequal(s, 'html') or striequal(s, 'div') or striequal(s, 'table') then exit(5);

  if striequal(s, '') then exit(100); //force closing of root element
end;

function TTreeParser.htmlTagAutoClosed(s: string): boolean;
begin
  //elements that should/must not have children
  result:=striequal(s,'meta') or
          striequal(s,'br') or
          striequal(s,'input') or
          striequal(s,'frame') or
          striequal(s,'hr')or
          striequal(s,'img');//or strliequal(s,'p');
end;

constructor TTreeParser.Create;
begin
  FElementStack := TList.Create;
  treeElementClass := TTreeElement;
  FTrimText:=true;
  FReadComments:=false;
  FReadProcessingInstructions:=false;
  FAutoDetectHTMLEncoding:=true;
  FTrees := TList.Create;

  FCurrentNamespaceDefinitions := TList.Create;
  FCurrentNamespaces := TNamespaceList.Create;
  FNamespaceGarbage := TNamespaceList.Create;
  globalNamespaces := TNamespaceList.Create;
  //FConvertEntities := true;
end;

destructor TTreeParser.destroy;
begin
  clearTrees;
  FElementStack.free;
  ftrees.Free;
  FCurrentNamespaces.Free;
  FCurrentNamespaceDefinitions.Free;
  FNamespaceGarbage.free;
  globalNamespaces.free;
  inherited destroy;
end;

procedure TTreeParser.clearTrees;
var
  i: Integer;
begin
  for i:=0 to FTrees.Count-1 do
    TTreeDocument(FTrees[i]).deleteAll();
  ftrees.Clear;
  for i:=0 to FNamespaceGarbage.Count-1 do
    tobject(FNamespaceGarbage[i]).free;
  FNamespaceGarbage.Clear;
end;


//like in TeXstudio
function isInvalidUTF8(const s: string): boolean;
var
  prev, cur: Integer;
  good, bad: Integer;
  i: Integer;
begin
  prev := 0;
  good := 0;
  bad := 0;
  for i := 1 to length(s) do begin
    cur := ord(s[i]);
    if (cur and $C0) = $80 then begin
      if (prev and $C0) = $C0 then good += 1
      else if (prev and $80) = $80 then bad += 1;
    end else begin
      if (prev and $C0) = $C0 then bad+=1
    end;
    prev := cur;
  end;
  result := good < 10 * bad;
end;

function TTreeParser.parseTree(html: string; uri: string; contentType: string): TTreeDocument;
  function encodingFromContentType(encoding: string): TEncoding;
  begin
    encoding := lowercase(encoding);
    if pos('charset=utf-8', encoding) > 0 then exit(eUTF8);
    if (pos('charset=windows-1252',encoding) > 0) or
       (pos('charset=latin1',encoding) > 0) or
       (pos('charset=iso-8859-1',encoding) > 0) then //also -15
        exit(eWindows1252);
    exit(eUnknown);
  end;

var
  el, attrib: TTreeElement;
  encMeta, encHeader: TEncoding;
begin
  FTemplateCount:=0;
  FElementStack.Clear;
  FCurrentTree:=nil;

  //FVariables.clear;
  if html='' then exit(nil);

  FCurrentFile:=html;
  FAutoCloseTag:=false;
  FCurrentNamespace := nil;

  //initialize root element
  //there are two reasons for an empty root element which doesn't exists in the file
  //1. it is necessary for the correct interpretion of xpath expressions html/... assumes
  //   that the current element is a parent of html
  //2. it serves as parent for multiple top level elements (althought they aren't allowed)
  FCurrentTree:=TTreeDocument.create;
  FCurrentTree.FCreator:=self;
  FCurrentTree.typ := tetOpen;
  FCurrentTree.FBaseURI:=uri;
  FCurrentTree.document := FCurrentTree;
  FCurrentElement:=FCurrentTree;
  FElementStack.Clear;
  FElementStack.Add(FCurrentElement);
  FTemplateCount:=1;
  FXmlHeaderEncoding := eUnknown;

  //parse
  if FParsingModel = pmHTML then simplehtmlparser.parseHTML(FCurrentFile,@enterTag, @leaveTag, @readText, @readComment)
  else simplehtmlparser.parseML(FCurrentFile,[],@enterTag, @leaveTag, @readText, @readComment);

  //close root element
  leaveTag('',0);

  if FAutoDetectHTMLEncoding  then begin
    FCurrentTree.FEncoding:=eUnknown;
    encHeader := encodingFromContentType(contentType);
    if parsingModel = pmHTML then
      encMeta := encodingFromContentType(TXQueryEngine.evaluateStaticXPath2('html/head/meta[@http-equiv=''content-type'']/@content', FCurrentTree).toString)
     else
      encMeta := encHeader;

    if encHeader = eUnknown then encHeader := FXmlHeaderEncoding;
    if encHeader = eUnknown then encHeader := encMeta;
    if encMeta  = eUnknown then encMeta := encHeader;
    if FXmlHeaderEncoding = eUnknown then FXmlHeaderEncoding := encHeader;
    if (encMeta = encHeader) and (encMeta = FXmlHeaderEncoding) and (encMeta <> eUnknown) then
      FCurrentTree.FEncoding := encMeta
    else begin //if in doubt, detect encoding and ignore meta/header data
      FCurrentTree.FEncoding:=eUTF8;
      el := FCurrentTree.next;
      while el <> nil do begin
        case el.typ of
          tetText: if isInvalidUTF8(el.value) then begin
            FCurrentTree.FEncoding:=eWindows1252;
            break;
          end;
          tetOpen: begin
            attrib := el.attributes;
            while attrib <> nil do begin
              if isInvalidUTF8(attrib.value) or isInvalidUTF8(attrib.reverse.value) then begin
                FCurrentTree.FEncoding:=eWindows1252;
                break;
              end;
              attrib := attrib.next;
            end;
            if FCurrentTree.FEncoding <> eUTF8 then break;
          end;
        end;
        el := el.next;
      end;
    end;

  end;

  FTrees.Add(FCurrentTree);
  result := FCurrentTree;
  FCurrentNamespaces.Clear;
  FCurrentNamespaceDefinitions.Clear;
//  if FRootElement = nil then
//    raise ETemplateParseException.Create('Ungültiges/Leeres Template');
end;

function TTreeParser.parseTreeFromFile(filename: string): TTreeDocument;
begin
  result := parseTree(strLoadFromFile(filename), filename);
end;

function TTreeParser.getLastTree: TTreeDocument;
begin
  if FTrees.Count = 0 then exit(nil);
  result := TTreeDocument(FTrees[FTrees.Count-1]);
end;

procedure TTreeParser.removeEmptyTextNodes(const whenTrimmed: boolean);
  function strIsEmpty(const s: string): boolean;
  var p: pchar; l: longint;
  begin
    p := pointer(s);
    l := length(s);
    strlTrimLeft(p, l);
    result := l = 0;
  end;

var
  temp: TTreeElement;
begin
  temp := getLastTree;
  if temp = nil then exit;
  while temp.next <> nil do begin
    while (temp.next <> nil) and (temp.next.typ = tetText) and ( (temp.next.value = '') or (whenTrimmed and (strIsEmpty(temp.next.value)))) do
      temp.removeAndFreeNext();
    temp := temp.next;
  end;
end;


function xmlStrEscape(s: string):string;
var
  i: Integer;
begin
  result := StringReplace(s, '<', '&lt;', [rfReplaceAll]); //TODO: escape all
end;

initialization
  XMLNamespace_XML := TNamespace.Create(XMLNamespaceUrl_XML, 'xml');
  XMLNamespace_XMLNS := TNamespace.Create(XMLNamespaceUrl_XMLNS, 'xmlns');
finalization
  XMLNamespace_XML.free;
  XMLNamespace_XMLNS.free;
end.

