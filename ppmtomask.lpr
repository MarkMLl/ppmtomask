(* Lazarus+FPC 2.1.0+3.2.0 on Linux Lazarus+FPC 2.1.0+3.2.0 on Linux Lazarus+FP *)

program ppmtomask;

(* Read a .ppm file (P3 or P6) as named by the final parameter of the command   *)
(* line, and generate a mask based either on the degree of pixel saturation or  *)
(* on a pixel being a specific colour.                                          *)
(*                                                                              *)
(* If the first parameter on the command line is -saturation then the second is *)
(* assumed to be a percentage, pixels with more than this saturation (e.g. pure *)
(* red or blue as distinct from medium-saturation purple) are output black with *)
(* everything else white.                                                       *)
(*                                                                              *)
(* If the first parameter on the command line is -colour then the second etc.   *)
(* are assumed to be RGB triplets each expressed as six hex digits, pixels with *)
(* any precisely-matched colour are output black with everything else white.    *)
(*                                                                              *)
(* The intention of this program is to generate masks to allow coloured lines   *)
(* or areas that have been overlaid onto a photograph to be extracted and       *)
(* reused. As a specific example, a synoptic weather chart might have its front *)
(* lines removed, a rainfall radar image overlaid, and the fronts replaced as   *)
(* the top layer.                                               MarkMLl.        *)

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, StrUtils;

type
  TPbmType= (NoFile, P1, P2, P3, P4, P5, P6, BadFile);

const
  {%H-}pbmPlain= [P1, P2, P3];
  pbmBinary= [P4, P5, P6];

type
  TPbm= record
          pbmInType: TpbmType;
          cols, rows, levels: integer;
          pbmInFile: file
        end;
  TPixel= record
            alpha: word;                (* Assume this is a dummy field, always zero *)
            red, green, blue: word
          end;
  TComponentArray= array[0..3] of word; (* Equivalent to TPixel                 *)


(* Read a single character advancing the file-read position by one, assume that
  the program will fail on error.
*)
function readChar(pbm: TPbm): AnsiChar;

begin
  BlockRead(pbm.pbmInFile, result, 1)
end { readChar } ;


(* Read a line of text, delimited by CR or LF, leaving the file-read position
  immediately beyond the delimiter; assume that the program will fail on error.

  This will normally be used to read and discard a comment.
*)
function readLine(pbm: TPbm): AnsiString;

var
  ch: AnsiChar;

begin
  result := '';
  BlockRead(pbm.pbmInFile, ch, 1);
  while not (ch in [#$0d, #$0a]) do begin
    result += ch;
    BlockRead(pbm.pbmInFile, ch, 1)
  end
end { readLine } ;


(* Silently discard whitespace and comments, leaving the file-read pointer on
  the non-whitespace character following; assume that the program will fail on
  error.

  Note that this backtracks since the non-whitespace character is likely to be
  significant to the next operation.
*)
procedure discardWhitespace(pbm: TPbm);

var
  ch: AnsiChar;

begin
  while true do begin
    BlockRead(pbm.pbmInFile, ch, 1);
    case ch of
      #$00..
      ' ': ;
      '#':  readLine(pbm)
    otherwise
      Seek(pbm.pbmInFile, FilePos(pbm.pbmInFile) - 1);
      break
    end
  end
end { discardWhitespace } ;


(* Read a +ve decimal number, delimited by a non-digit, leaving the file-read
  position on the delimiter; assume that the program will fail on error.

  The rationale for the next operation re-reading the delimiter is that the
  NetPBM specification appears to allow a number to be immediately followed by
  a comment which must be recognised and discarded in its entirety.
*)
function readDecimal(pbm: TPbm): integer;

var
  ch: AnsiChar;
  num: AnsiString= '';

begin
  discardWhitespace(pbm);
  while true do begin
    BlockRead(pbm.pbmInFile, ch, 1);
    if ch in ['0'..'9'] then
      num += ch
    else begin
      Seek(pbm.pbmInFile, FilePos(pbm.pbmInFile) - 1);
      break
    end
  end;
  result := StrToInt(num)
end { readDecimal } ;


(* Read a pixel represented by one to three decimal numbers depending on the
  type of the file, delimited by a non-digit, leaving the file-read position on
  the delimiter; assume that the program will fail on error.

  The rationale for the next operation re-reading the delimiter (in the case of
  a decimal number) is that the NetPBM specification appears to allow a number
  to be immediately followed by a comment which must be recognised and discarded
  in its entirety.
*)
function readPixel(pbm: TPbm; startRow: boolean= false): TPixel;

const
  bitsBuffered: integer= 0;             (* Static variable                      *)
  bitBuffer: byte= 0;                   (* Static variable                      *)

var
  ls, ms: byte;

begin
  result.alpha := 0;
  if startRow then begin
    bitsBuffered := 0;
    bitBuffer := 0
  end;
  case pbm.pbmInType of
    P1: begin                           (* ASCII 0 or 1 per pixel               *)
          if ReadDecimal(pbm) = 0 then
            result.red := 0
          else
            result.red := 255;
          result.green := result.red;
          result.blue := result.red
        end;
    P2: begin                           (* One decimal number per pixel         *)
          result.red := ReadDecimal(pbm);
          result.green := result.red;
          result.blue := result.red
        end;
    P3: begin                           (* Three decimal numbers per pixel      *)
          result.red := ReadDecimal(pbm);
          result.green := ReadDecimal(pbm);
          result.blue := ReadDecimal(pbm)
        end;
    P4: begin                           (* Eight pixels ber byte                *)
          if bitsBuffered = 0 then begin
            BlockRead(pbm.pbmInFile, bitBuffer, 1);
            bitsBuffered := 8
          end;
          if bitBuffer and $80 = $00 then
            result.red := 0
          else
            result.red := 255;
          bitBuffer := bitBuffer << 1;
          bitsBuffered -= 1;
          result.green := result.red;
          result.blue := result.red
        end;

(* In the case of the binary formats, remember that the pixel components are    *)
(* each 16 bits (i.e. two bytes) with endianness specific to the computer type, *)
(* while we either want to read a single byte per component or two bytes which  *)
(* are defined by the file format to have the more significant byte first.      *)

    P5: begin
          if pbm.levels <= 256 then     (* One byte per pixel                   *)
            ms := 0
          else                          (* Two bytes per pixel, MSB first       *)
            BlockRead(pbm.pbmInFile, ms, 1);
          BlockRead(pbm.pbmInFile, ls, 1);
          result.red := (ms << 8) + ls;
          result.green := result.red;
          result.blue := result.red
        end;
    P6: if pbm.levels <= 256 then begin (* Three bytes per pixel                *)
          BlockRead(pbm.pbmInFile, ls, 1);
          result.red := ls;
          BlockRead(pbm.pbmInFile, ls, 1);
          result.green := ls;
          BlockRead(pbm.pbmInFile, ls, 1);
          result.blue := ls
        end else begin                  (* Six bytes per pixel, MSB first       *)
          BlockRead(pbm.pbmInFile, ms, 1);
          BlockRead(pbm.pbmInFile, ls, 1);
          result.red := (ms << 8) + ls;
          BlockRead(pbm.pbmInFile, ms, 1);
          BlockRead(pbm.pbmInFile, ls, 1);
          result.green := (ms << 8) + ls;
          BlockRead(pbm.pbmInFile, ms, 1);
          BlockRead(pbm.pbmInFile, ls, 1);
          result.blue := (ms << 8) + ls
        end
  otherwise
    result.red := 0;
    result.green := 0;
    result.blue := 0
  end
end { readPixel } ;


(* The specification of the NetPBM file format is sufficiently woolly to make it
  necessary to parse it as a binary file irrespective of whether the format is
  binary or text ("plain"). This is caused in particular by the possibility of
  arbitrary numbers of whitespace characters in the header and by the fact that
  these might or might not indicate line breaks, and also by the possibility
  that comment text might appear at any point (even if in practice it is most
  likely to be in or immediately after the header).

  On exit from this function with the type set to a valid file, and the file-
  read position will be immediately past the final field of the header, which in
  practice might leave it on further whitespace or a comment but not yet on the
  data representing the first pixel.
*)
function readHeader(const name: AnsiString): TPbm;

begin
  with result do begin
    pbmInType := NoFile;
    cols := 0;
    rows := 0;
    levels := 2
  end;
  if not FileExists(name) then
    exit;                               (* Returning NoFile                     *)
  Assign(result.pbmInFile, name);
  Reset(result.pbmInFile, 1);
  result.pbmInType := BadFile;
  try
    if readChar(result) <> 'P' then
      exit;                             (* Via finally block, returning NoFile  *)
    with result do begin
      case readChar(result) of
        '1': pbmInType := P1;
        '2': pbmInType := P2;
        '3': pbmInType := P3;
        '4': pbmInType := P4;
        '5': pbmInType := P5;
        '6': pbmInType := P6
      otherwise
        exit                            (* Via finally block, returning BadFile *)
      end;

(* If we've got here, we know that the file exists and is readable and believe  *)
(* that it's a valid NetPBM file. The magic number may be followed by any       *)
(* amount of whitespace.                                                        *)

      cols := readDecimal(result);
      rows := readDecimal(result);
      case pbmInType of
        P1, P4: ;
        P2, P5,
        P3, P6: levels := readDecimal(result) + 1
      end
    end
  finally
    if result.pbmInType = BadFile then
      CloseFile(result.pbmInFile)
  end
end { readHeader } ;


  //############################################################################
 //      1         2         3         4         5         6         7         8
// 45678901234567890123456789012345678901234567890123456789012345678901234567890


operator <>(p1, p2: TPixel): boolean; inline;

begin
  result := QWord(p1) <> QWord(p2)
end { <> } ;


(* Options at the start of the command line should be ignored, these are
  followed by one or more six-digit hex numbers representing RGB values that
  result in a black output pixel. Output is monochrome, text or binary as
  determined by the presence of a -plain parameter.
*)
procedure doColours(header: TPbm; pbmOutType: TPbmType; invert: boolean);

(* Irish Met Office front colours for test purposes:                            *)
(*                                                                              *)
(* Blue (cold)          0,38,193       0026c1                                   *)
(* Red (warm)           199,37,0       c72500                                   *)
(* Purple (occluded)    179,39,179     b327b3                                   *)
(*                                                                              *)
(* Hence to test this use e.g.  -plain -colours 0026c1 c72500 b327b3 atl.ppm    *)

var
  i, j, k, l: integer;
  matches: array of TPixel;
  pixel: TPixel;
  b: byte;
  pixels: qword= 0;                     (* These for debugging                  *)
  hits: qword= 0;

begin
  case PbmOutType of
    P1: WriteLn('P1');
    P4: WriteLn('P4');
  otherwise
    Halt
  end;
  WriteLn('# Colour mask derived from ', ParamStr(ParamCount()));
  WriteLn(header.cols, ' ', header.rows);
  for i := 1 to ParamCount() - 1 do begin
    if ParamStr(i)[1] = '-' then        (* It's an option                       *)
      continue;
    SetLength(matches, Length(matches) + 1);
    k := Hex2Dec(ParamStr(i));          (* Exception on error                   *)
    if Length(ParamStr(i)) <= 8 then
      with matches[Length(matches) - 1] do begin
        alpha := 0;
        red := (k >> 16) and $ff;
        green := (k >> 8) and $ff;
        blue := (k >> 0) and $ff;

(* The user should not be expected to know that the current input file has 16   *)
(* rather than 8 bits per component of the pixel, hence that the colour match   *)
(* should be more than the usual 8 bits per pixel. Instead, I'm LSB-extending   *)
(* each value from the command line.                                            *)

        if header.levels > 256 then begin
          if not Odd(red) then
            red := red << 8
          else
            red := (red << 8) + $ff;
          if not Odd(green) then
            green := green << 8
          else
            green := (green << 8) + $ff;
          if not Odd(blue) then
            blue := blue << 8
          else
            blue := (blue << 8) + $ff
        end
      end
    else
      with matches[Length(matches) - 1] do begin
        alpha := 0;
        red := (k >> 32) and $ffff;
        green := (k >> 16) and $ffff;
        blue := (k >> 0) and $ffff
      end
  end;

(* Iterate over the input pixels looking for colour matches.                    *)

  case PbmOutType of
    P1: begin                           (* ASCII 0 or 1 per pixel               *)
          for i := 0 to header.rows - 1 do begin
            l := 0;
            for j := 0 to header.cols - 1 do begin
              pixel := readPixel(header, j = 0);
              k := 0;
              while (k < Length(matches)) and (pixel <> matches[k]) do
                k += 1;
              if (k = Length(matches)) xor invert then
                Write('0 ')
              else begin
                Write('1 ');
                hits += 1
              end;
              pixels += 1;
              l += 2;
              if l >= 70 then begin
                WriteLn;
                l := 0
              end
            end;
            if l <> 0 then
              WriteLn
          end;
          WriteLn
        end;
    P4: begin                           (* Eight pixels per byte                *)
          for i := 0 to header.rows - 1 do begin
            l := 0;
            b := 0;
            for j := 0 to header.cols - 1 do begin
              pixel := readPixel(header, j = 0);
              k := 0;
              while (k < Length(matches)) and (pixel <> matches[k]) do
                k += 1;
              if (k = Length(matches)) xor invert then
                b := b << 1
              else begin
                b := (b << 1) + 1;
                hits += 1
              end;
              pixels += 1;
              l += 1;
              if l = 8 then begin
                Write(AnsiChar(b));
                l := 0;
                b := 0
              end
            end;
            if l <> 0 then begin
              while l < 8 do begin
                b := b << 1;
                l += 1
              end;
              Write(AnsiChar(b))
            end
          end
        end
  otherwise
  end
end { doColours } ;


  //############################################################################
 //      1         2         3         4         5         6         7         8
// 45678901234567890123456789012345678901234567890123456789012345678901234567890


(* This should produce a viable saturation when the dominant colour is one of
  the RGB primaries.
*)
function primarySat(greatest, lesser, least: integer; threshold: double): boolean; inline;

var
  dominant, opponent: word;
  purity: double;

begin
  dominant := greatest;
  opponent := Round(Sqrt((Sqr(lesser) + Sqr(least)) / 2));
  purity := 100.0 / (1 + (lesser - least) / 512);

(* The dominant and opponent are the magnitudes of the primary and              *)
(* complementary components. The purity is the extent to which the colour is    *)
(* off-axis i.e. isn't quite one of the standard primary or complementary hues. *)

  if dominant <> 0 then
    result := (purity * (dominant - opponent) / dominant)>= threshold
  else
    result := false
end { primarySat } ;


(* This should produce a viable saturation when the dominant colour is a mixture
  of two RGB primaries.
*)
function complementarySat(greatest, lesser, least: integer; threshold: double): boolean; inline;

var
  dominant, opponent: word;
  purity: double;

begin
  dominant := Round(Sqrt((Sqr(greatest) + Sqr(lesser)) / 2 ));
  opponent := least;
  purity := 100.0 / (1 + (greatest - lesser) / 512);

(* The dominant and opponent are the magnitudes of the complementary and        *)
(* primary components. The purity is the extent to which the colour is off-axis *)
(* i.e. isn't quite one of the standard primary or complementary hues.          *)

  if dominant <> 0 then
    result := (purity * (dominant - opponent) / dominant) >= threshold
  else
    result := false
end { complementarySat } ;


(* Investigate the level of saturation of a pixel, assuming that the components
  are sorted so we no longer know the hue.
*)
function complexSat(greatest, lesser, least: integer; threshold: double): boolean; inline;

// TODO : Optimisation: adjust order based on number of times short-circuit is taken.
// Whenever the primary exceeds the threshold the complementary function won't
// be called. But if the source image actually had more matching complementary
// colours, the logical expression would be better the other way round.
//
// Experiment suggests that with the weather satellite and rainfall radar images
// I'm processing, that might result in about a 5% improvement in wall-clock
// execution time, which I believe is dominated by disc access. As such it is
// probably not worth further investigation.

begin
  result := primarySat(greatest, lesser, least, threshold) or
                                complementarySat(greatest, lesser, least, threshold)
end { complexSat } ;


(* Return true if the saturation- according to some appropriate algorithm- of
  the RGB pixel exceeds the threshold percentage.
*)
function saturated(p: TPixel; threshold: double): boolean; inline;

var
  p2: TComponentArray;                  (* Equivalence asserted at start of run *)
  w: word;
  i: integer;

begin
  TPixel(p2) := p;
  Assert(p2[0] = 0, 'Alpha component non-zero.');

(* Sort the components of the pixel. This doesn't, however, tell us whether the *)
(* hue represents a primary or complementary colour, which has implications for *)
(* the saturation test.                                                         *)

// TODO : Optimisation: since the swaps are of adjacent components use a 16-bit shift.
//
// Experiment suggests that this confers no significant improvement.

  if p2[2] < p2[1] then begin
    w := p2[1];
    p2[1] := p2[2];
    p2[2] := w
  end;
  if p2[3] < p2[2] then begin
    w := p2[2];
    p2[2] := p2[3];
    p2[3] := w
  end;
  if p2[2] < p2[1] then begin
    w := p2[1];
    p2[1] := p2[2];
    p2[2] := w
  end;

(* Investigate the extent to which the pixel is saturated. Since the components *)
(* have been sorted, hue information has been lost.                             *)

  result := complexSat(p2[3], p2[2], p2[1], threshold) (* Element [0] always zero *)
end { saturated } ;


(* Options at the start of the command line should be ignored, these are
  followed by a single decimal number representing the minimum saturation
  percentage which is to result in a black output pixel. Output is monochrome,
  text or binary as determined by the presence of a -plain parameter.
*)
procedure doSaturation(header: TPbm; pbmOutType: TPbmType; invert: boolean);

(* To test this use e.g.  -plain -saturation 68.0% sat.ppm                      *)

var
  i, j, l: integer;
  threshold: double= 50.0;
  pixel: TPixel;
  b: byte;
  pixels: qword= 0;                     (* These for debugging                  *)
  hits: qword= 0;

begin
  case PbmOutType of
    P1: WriteLn('P1');
    P4: WriteLn('P4');
  otherwise
    Halt
  end;
  WriteLn('# Saturation mask derived from ', ParamStr(ParamCount()));
  WriteLn(header.cols, ' ', header.rows);
  for i := 1 to ParamCount() - 1 do begin
    if ParamStr(i)[1] = '-' then        (* It's an option                       *)
      continue;
    threshold := StrToFloat(ReplaceStr(ParamStr(i), '%', '')) (* Exception on error *)
  end;

(* Iterate over the input pixels looking for saturation triggers.               *)

  case PbmOutType of
    P1: begin                           (* ASCII 0 or 1 per pixel               *)
          for i := 0 to header.rows - 1 do begin
            l := 0;
            for j := 0 to header.cols - 1 do begin
              pixel := readPixel(header, j = 0);
              if saturated(pixel, threshold) xor invert then
                Write('1 ')
              else begin
                Write('0 ');
                hits += 1
              end;
              pixels += 1;
              l += 2;
              if l >= 70 then begin
                WriteLn;
                l := 0
              end
            end;
            if l <> 0 then
              WriteLn
          end;
          WriteLn
        end;
    P4: begin                           (* Eight pixels per byte                *)
          for i := 0 to header.rows - 1 do begin
            l := 0;
            b := 0;
            for j := 0 to header.cols - 1 do begin
              pixel := readPixel(header, j = 0);
              if saturated(pixel, threshold) xor invert then
                b := (b << 1) + 1
              else begin
                b := b << 1;
                hits += 1
              end;
              pixels += 1;
              l += 1;
              if l = 8 then begin
                Write(AnsiChar(b));
                l := 0;
                b := 0
              end
            end;
            if l <> 0 then begin
              while l < 8 do begin
                b := b << 1;
                l += 1
              end;
              Write(AnsiChar(b))
            end
          end
        end
  otherwise
  end
end { doSaturation } ;


  //############################################################################
 //      1         2         3         4         5         6         7         8
// 45678901234567890123456789012345678901234567890123456789012345678901234567890


var
  header: TPbm;
  plain: boolean= false;
  invert: boolean= false;
  colours: boolean= false;
  {%H-}residue: int64= -1;
  i: integer;


begin
  Assert(SizeOf(TPixel) = 4 * SizeOf(word), 'TPixelSize bad 1');
  Assert(SizeOf(TPixel) = SizeOf(TComponentArray), 'TPixelSize bad 1');
  if (ParamCount() = 0) or (Pos('-h', LowerCase(ParamStr(1))) > 0) or
                                        (Pos('/h', LowerCase(ParamStr(1))) > 0) or
                                        (Pos('/?', LowerCase(ParamStr(1))) > 0) then begin
    WriteLn();
    WriteLn('Usage: ppmtomask [OPTIONS]... filename');
    WriteLn();
    WriteLn('Read the input file specified on the command line and generate a mask');
    WriteLn('based on an explicit list of matched colours or a specified saturation');
    WriteLn('threshold. The output is always written to stdout with the expectation');
    WriteLn('that it is redirected to a file.');
    WriteLn();
    WriteLn('Supported options are as below:');
    WriteLn();
    WriteLn('  --help         This help text.');
    WriteLn();
    WriteLn('  --plain        The output format is NetPBM text (i.e. type P1) rather');
    WriteLn('                 than the default binary (type P4).');
    WriteLn();
    WriteLn('  --invert       Unmatched background is black rather than white.');
    WriteLn();
    WriteLn('  --colours hhh  hhh is a sequence of six hex digits indicating an RGB');
    WriteLn('                 colour to be matched precisely. Multiple digit sequences');
    WriteLn('                 should be separated by spaces.');
    WriteLn();
    WriteLn('  --saturation d d is a floating point percentage, with optional %.');
    WriteLn();
    WriteLn('One or other of the --colour or --saturation options must be specified,');
    WriteLn('but not both.');
    WriteLn();
    WriteLn('Exit status:');
    WriteLn();
    WriteLn(' 0  Normal termination');
    WriteLn(' 1  Missing or bad input file');
    WriteLn()
  end else begin
    ExitCode := 1;
    header := readHeader(ParamStr(ParamCount()));
    case header.pbmInType of
      NoFile:  WriteLn(StdErr, 'Cannot open input file "', ParamStr(ParamCount()), '"');
      BadFile: WriteLn(StdErr, 'Unable to process input file "', ParamStr(ParamCount()), '"')
    otherwise

(* If the input is a binary format then expect one delimiter character after    *)
(* the header which still needs to be discarded, and which can't easily be      *)
(* distinguished from data.                                                     *)

      if header.pbmInType in PbmBinary then
        readChar(header);

      for i := 1 to ParamCount() do begin
        if (Pos('-plain', ParamStr(i)) > 0) or (Pos('-text', ParamStr(i)) > 0) then
          plain := true;
        if (Pos('-inv', ParamStr(i)) > 0) or (Pos('-not', ParamStr(i)) > 0) then
          invert := true;
        if Pos('-col', ParamStr(i)) > 0 then
          colours := true
      end;
      if plain then
        if colours then
          doColours(header, P1, invert)
        else
          doSaturation(header, P1, invert)
      else
        if colours then
          doColours(header, P4, invert)
        else
          doSaturation(header, P4, invert);

(* If the input is a binary format then expect the file-read position to now be *)
(* at precisely the end of file.                                                *)

      if header.pbmInType in PbmBinary then
        residue := FileSize(header.pbmInFile) - FilePos(header.pbmInFile);

      CloseFile(header.pbmInFile);
      ExitCode := 0
    end
  end
end.

