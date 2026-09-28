unit uNFCe;

interface

uses
  uGlobais,
  SysUtils,
  Variants,
  Math,
  Data.DB,
  JSON,
  ACBrDFeSSL,
  ACBrDFe,
  ACBrDFe.Conversao,
  ACBrNFe,
  pcnConversao,
  conexao,
  Windows, Messages, Classes, Graphics,
  System.NetEncoding,
  System.SyncObjs,
  DataSet.Serialize,
  Controls, Forms, Dialogs, ExtCtrls, StdCtrls,
  Spin, Buttons, ComCtrls, OleCtrls, SHDocVw, ACBrMail,
  ACBrPosPrinter, ACBrNFeDANFeESCPOS, ACBrNFeDANFEClass, ACBrDANFCeFortesFr,
  ACBrDFeReport, ACBrDFeDANFeReport, ACBrNFeDANFeRLClass, ACBrBase,
  ShellAPI, XMLIntf, XMLDoc, zlib, ACBrIntegrador,
  ACBrDANFCeFortesFrA4, uRequisicao, FireDAC.Stan.Intf, FireDAC.Stan.Option,
  FireDAC.Stan.Param, FireDAC.Stan.Error, FireDAC.DatS, FireDAC.Phys.Intf,
  FireDAC.DApt.Intf, FireDAC.Comp.DataSet, FireDAC.Comp.Client,
  ACBrValidador, System.Zip, System.RegularExpressions, REST.Types,
  REST.Response.Adapter, REST.Client, Data.Bind.Components,
  Data.Bind.ObjectScope,
  strutils, TypInfo, DateUtils, synacode, blcksock, FileCtrl, Grids,
  IniFiles, Printers, System.IOUtils,
  ACBrUtil.Base, ACBrUtil.FilesIO, ACBrUtil.DateTime, ACBrUtil.Strings,
  ACBrUtil.XMLHTML,
  pcnAuxiliar, pcnConversaoNFe, pcnNFeRTXT,
  pcnRetConsReciDFe,
  ACBrDFeConfiguracoes, ACBrDFeOpenSSL, ACBrDFeUtil,
  ACBrNFeNotasFiscais, ACBrNFeConfiguracoes, ACBrNFe.Classes;

type
  TNFCeImpressora = record
    Driver: String;
    TipoImpressao: Integer;
  end;

function GerarNFCe(codigo: Integer): String;
function TransmitirNFCe(codigo: Integer; imprimir: Boolean = True): String;
function ProximoNumeroNFCe(conexao: TConexao): Integer;
procedure ImprimirNFCeChave(const chave: String);
function CancelarNFCe(const chave, motivo: String): String;
procedure EnviarNotaFiscalNFCe(const chave, caminho: String);
procedure DeletarNFCeBase(const chave: String);
procedure EnviarEmailNFCe(const chave, emailDestino: String);
procedure IniciarThreadEmissaoNFCe;
procedure PararThreadEmissaoNFCe;
procedure IniciarThreadConsultaDFe;
procedure PararThreadConsultaDFe;
procedure IniciarThreadStatusServicoNFe;
procedure PararThreadStatusServicoNFe;
function GetPagamento(codigo: Integer): TJsonArray;
function GetProdutos(codigo: Integer): TJsonArray;
function GetComplemento(codigo: Integer): TJsonArray;
function CreateAcbrNf(conexao: TConexao): TACBrNFe;
function GetNotasPendentesContabilidade: TJsonArray;
function ConsultarDFeSefaz(const CNPJ: String = ''): TJSONObject;
function ConsultarXMLDFePorChave(const chave: String): TJSONObject;
function SimularImportacaoDFeArquivo(const caminho: String): TJSONObject;
function ManifestarDFePorChave(const chave, Tipo, Justificativa: String;
  const Origem: String = 'manual'): TJSONObject;
function ConsultarStatusServicoNFe: TJSONObject;
function MontarJSONStatusServicoNFeGravado: TJSONObject;
procedure RegistrarErroNFCe(codigo: Integer; const erro: String);
procedure MarcarNotaSincronizadaContabilidade(const chave, caminho,
  path: String);

function GetImpressora(codigo: Integer; conexao: TConexao): TNFCeImpressora;
procedure EmailFiscal(chave, email: String);
function StatusServicoNFeDisponivel(var motivo: String): Boolean;

implementation

type
  TNFCeTotais = record
    ValorProdutos: Double;
    ValorDesconto: Double;
    ValorOutros: Double;
    ValorNF: Double;
    BaseICMS: Double;
    ValorICMS: Double;
    ValorPIS: Double;
    ValorCOFINS: Double;
    ValorTributos: Double;
    TributosFederal: Double;
    TributosEstadual: Double;
    ValorItens: Double;
    BaseIBSCBS: Double;
    ValorIBSUF: Double;
    ValorIBSMun: Double;
    ValorCBS: Double;
    TotalPagamento: Double;
  end;

  TNFCeComplemento = record
    TaxaEntrega: Double;
    TaxaDesconto: Double;
    CPF: String;
    Nome: String;
  end;

  TThreadEmissaoNFCe = class(TThread)
  private
    FLimite: Integer;
    FIntervaloMS: Integer;
    procedure ProcessarFila;
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

  TThreadConsultaDFe = class(TThread)
  private
    FIntervaloMS: Integer;
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

  TThreadStatusServicoNFe = class(TThread)
  private
    FIntervaloMS: Integer;
    function ProximoIntervalo(const Status: TJSONObject): Integer;
    procedure AguardarIntervalo;
  protected
    procedure Execute; override;
  public
    constructor Create;
  end;

function ParametroStr(conexao: TConexao; const chave: String): String; forward;
function ParametroInt(conexao: TConexao; const chave: String;
  valorPadrao: Integer): Integer; forward;

function PathSchemasNFe(conexao: TConexao): String; forward;
function DFeHabilitado(conexao: TConexao): Boolean; forward;
function ManifestarDFePendentesAutomatico: Integer; forward;
procedure AtualizarXMLDFeBanco(conexao: TConexao;
  const chave, XML: String); forward;
function ImportarNotaFiscalDFeXML(conexao: TConexao; const XML: String)
  : Boolean; forward;
function BlocoTagXML(const XML, Nome: String): String; forward;
function ValorTagXML(const XML, Nome: String): Double; forward;

function ParametroStrPadrao(conexao: TConexao;
  const chave, valorPadrao: String): String;
begin
  Result := Trim(ParametroStr(conexao, chave));
  if Result = '' then
    Result := valorPadrao;
end;

var
  ThreadEmissaoNFCe: TThreadEmissaoNFCe = nil;
  ThreadConsultaDFe: TThreadConsultaDFe = nil;
  ThreadStatusServicoNFe: TThreadStatusServicoNFe = nil;
  CriticalConsultaDFe: TCriticalSection = nil;
  CriticalStatusServicoNFe: TCriticalSection = nil;
  ProximaConsultaDFe: TDateTime = 0;
  UltimoStatusServicoNFeJSON: String = '';
  UltimoStatusServicoNFeCStat: Integer = 0;
  UltimoStatusServicoNFeMotivo: String = '';
  UltimoStatusServicoNFeDataHora: TDateTime = 0;

const
  PARAM_DFE_ULTIMA_EXECUCAO = 'dfe_ultima_execucao';
  PARAM_DFE_ULTIMO_NSU = 'dfe_ultimo_nsu';

function JsonObj(arrayJson: TJsonArray; indice: Integer): TJSONObject;
begin
  Result := TJSONObject(arrayJson.Items[indice]);
end;

function BuscarFilaNFCe(limite: Integer): TJsonArray;
var
  conexao: TConexao;
  IntervaloReenvioMinutos: Integer;
begin
  if limite <= 0 then
    limite := 10;
  if limite > 50 then
    limite := 50;
  conexao := TConexao.Create('BuscarFilaNFCe');
  try
    IntervaloReenvioMinutos := ParametroInt(conexao,
      'nfce_reenvio_erro_minutos', 10);
    if IntervaloReenvioMinutos <= 0 then
      IntervaloReenvioMinutos := 10;
    if IntervaloReenvioMinutos > 1440 then
      IntervaloReenvioMinutos := 1440;
    conexao.SQL.Text := 'UPDATE pedido SET nfce_status = "PROCESSANDO", ' +
      'nfce_lock = NOW() WHERE nfce_emite = 1 ' +
      'AND (nfce_status = "" OR nfce_status is null OR nfce_status = "PENDENTE" '
      + 'OR (nfce_status = "ERRO" AND (nfce_lock IS NULL OR nfce_lock <= DATE_SUB(NOW(), INTERVAL '
      + IntToStr(IntervaloReenvioMinutos) + ' MINUTE)))) ' +
      'AND (codigo > 0) AND data_pedido >= DATE_FORMAT(CURDATE(), "%Y-%m-01") '
      + 'ORDER BY codigo LIMIT ' + IntToStr(limite);
    conexao.ExecuteSQL;
    conexao.SQL.Text := 'SELECT * FROM pedido ' +
      'WHERE nfce_status = "PROCESSANDO" ' +
      'AND nfce_lock >= DATE_SUB(NOW(), INTERVAL 1 MINUTE) ' +
      'AND data_pedido >= DATE_FORMAT(CURDATE(), "%Y-%m-01") ' + 'LIMIT ' +
      IntToStr(limite);
    Result := conexao.ConsultaSQL;
  finally
    conexao.Free;
  end;
end;

function JsonStr(obj: TJSONObject; const campo: String): String;
var
  valor: TJSONValue;
  par: TJSONPair;
  I: Integer;
begin
  Result := '';
  if not Assigned(obj) then
    Exit;

  valor := obj.GetValue(campo);
  if Assigned(valor) then
  begin
    Result := valor.Value;
    Exit;
  end;

  for I := 0 to obj.Count - 1 do
  begin
    par := obj.Pairs[I];
    if Assigned(par) and SameText(par.JsonString.Value, campo) then
    begin
      if Assigned(par.JsonValue) then
        Result := par.JsonValue.Value;
      Exit;
    end;
  end;
end;

function JsonStrAny(obj: TJSONObject; const campo1, campo2: String): String;
begin
  Result := JsonStr(obj, campo1);
  if (Result = '') and (campo2 <> '') then
    Result := JsonStr(obj, campo2);
end;
function JsonFloat(obj: TJSONObject; const campo: String): Double;
var
  texto: String;
  fs: TFormatSettings;
begin
  texto := JsonStr(obj, campo);
  fs := TFormatSettings.Create;
  fs.DecimalSeparator := '.';
  Result := StrToFloatDef(texto, 0, fs);
  if Result = 0 then
    Result := StrToFloatDef(StringReplace(texto, '.', ',', [rfReplaceAll]), 0);
end;

function JsonFloatName(obj: TJSONObject; const campo1, campo2: String): Double;
var
  texto: String;
  fs: TFormatSettings;
begin
  texto := JsonStrAny(obj, campo1, campo2);
  fs := TFormatSettings.Create;
  fs.DecimalSeparator := '.';
  Result := StrToFloatDef(texto, 0, fs);
  if Result = 0 then
    Result := StrToFloatDef(StringReplace(texto, '.', ',', [rfReplaceAll]), 0);
end;
function JsonInt(obj: TJSONObject; const campo: String): Integer;
begin
  Result := StrToIntDef(JsonStr(obj, campo), 0);
end;

function SetEnumPropPorNome(obj: TObject;
  const Propriedade, valor: String): Boolean;
var
  Info: PPropInfo;
  EnumValue: Integer;
  Kind: TTypeKind;
begin
  Result := False;
  if (not Assigned(obj)) or (Trim(valor) = '') then
    Exit;

  Info := GetPropInfo(obj, Propriedade);
  if not Assigned(Info) then
    Exit;

  Kind := Info.PropType^.Kind;
  if Kind in [tkString, tkLString, tkWString, tkUString] then
  begin
    SetStrProp(obj, Info, valor);
    Result := True;
    Exit;
  end;

  if Kind = tkEnumeration then
  begin
    EnumValue := GetEnumValue(Info.PropType^, valor);
    if EnumValue < 0 then
      Exit;

    SetOrdProp(obj, Info, EnumValue);
    Result := True;
  end;
end;


function CSTIBSCBSPorCodigo(const Codigo: String): TCSTIBSCBS;
begin
  if Codigo = '200' then
    Result := cst200
  else if Codigo = '220' then
    Result := cst220
  else if Codigo = '510' then
    Result := cst510
  else
    Result := cst000;
end;

procedure AlimentarIBSCBSACBr(Produto: TDetCollectionItem; Item: TJSONObject;
  BaseCalculo: Double; var Totais: TNFCeTotais);
var
  CSTCodigo, ClassTrib: String;
  CSTEnum: TCSTIBSCBS;
  AliqIBSUF, AliqIBSMun, AliqCBS: Double;
  RedIBS, RedCBS: Double;
  NomeProduto: String;
begin
  if not Assigned(Produto) then
    Exit;

  NomeProduto := '[' + JsonStr(Item, 'code') + '] ' + JsonStr(Item, 'name');

  CSTCodigo := Trim(JsonStrAny(Item, 'ibsCbsCst', 'ibs_cbs_cst'));
  if CSTCodigo = '' then
    CSTCodigo := '000';
  CSTEnum := CSTIBSCBSPorCodigo(CSTCodigo);
  ClassTrib := Trim(JsonStrAny(Item, 'ibsCbsClassTrib', 'ibs_cbs_class_trib'));
  if ClassTrib = '' then
    ClassTrib := '000001';

  RedIBS := JsonFloatName(Item, 'ibsCbsPredIbs', 'ibs_cbs_pred_ibs');
  RedCBS := JsonFloatName(Item, 'ibsCbsPredCbs', 'ibs_cbs_pred_cbs');
  AliqIBSUF := JsonFloatName(Item, 'ibsUfAliq', 'ibs_uf_aliq') * (Max(0, 100 - RedIBS) / 100);
  AliqIBSMun := JsonFloatName(Item, 'ibsMunAliq', 'ibs_mun_aliq') * (Max(0, 100 - RedIBS) / 100);
  AliqCBS := JsonFloatName(Item, 'cbsAliq', 'cbs_aliq') * (Max(0, 100 - RedCBS) / 100);

  with Produto.Imposto.IBSCBS do
  begin
    CST := CSTEnum;
    cClassTrib := ClassTrib;
    gIBSCBS.vBC := BaseCalculo;
    gIBSCBS.gIBSUF.pIBSUF := AliqIBSUF;
    gIBSCBS.gIBSUF.vIBSUF := RoundTo((BaseCalculo * AliqIBSUF) / 100, -2);
    if RedIBS > 0 then
    begin
      gIBSCBS.gIBSUF.gRed.pRedAliq := RedIBS;
      gIBSCBS.gIBSUF.gRed.pAliqEfet := AliqIBSUF;
    end;

    gIBSCBS.gIBSMun.pIBSMun := AliqIBSMun;
    gIBSCBS.gIBSMun.vIBSMun := RoundTo((BaseCalculo * AliqIBSMun) / 100, -2);
    gIBSCBS.vIBS := gIBSCBS.gIBSUF.vIBSUF + gIBSCBS.gIBSMun.vIBSMun;
    if RedIBS > 0 then
    begin
      gIBSCBS.gIBSMun.gRed.pRedAliq := RedIBS;
      gIBSCBS.gIBSMun.gRed.pAliqEfet := AliqIBSMun;
    end;

    gIBSCBS.gCBS.pCBS := AliqCBS;
    gIBSCBS.gCBS.vCBS := RoundTo((BaseCalculo * AliqCBS) / 100, -2);
    if RedCBS > 0 then
    begin
      gIBSCBS.gCBS.gRed.pRedAliq := RedCBS;
      gIBSCBS.gCBS.gRed.pAliqEfet := AliqCBS;
    end;
  end;

  Totais.BaseIBSCBS := Totais.BaseIBSCBS + BaseCalculo;
  Totais.ValorIBSUF := Totais.ValorIBSUF +
    RoundTo((BaseCalculo * AliqIBSUF) / 100, -2);
  Totais.ValorIBSMun := Totais.ValorIBSMun +
    RoundTo((BaseCalculo * AliqIBSMun) / 100, -2);
  Totais.ValorCBS := Totais.ValorCBS +
    RoundTo((BaseCalculo * AliqCBS) / 100, -2);
end;

constructor TThreadEmissaoNFCe.Create;
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FLimite := 50;
  FIntervaloMS := 5000;
end;

procedure TThreadEmissaoNFCe.Execute;
begin
  FormatSettings.DecimalSeparator := '.';
  while not Terminated do
  begin
    try
      ProcessarFila;
    except
    end;
    Sleep(FIntervaloMS);
  end;
end;

procedure TThreadEmissaoNFCe.ProcessarFila;
var
  fila: TJsonArray;
  I, codigo: Integer;
  Item: TJSONObject;
begin
  fila := BuscarFilaNFCe(FLimite);
  try
    for I := 0 to fila.Count - 1 do
    begin
      if Terminated then
        Break;
      Item := JsonObj(fila, I);
      codigo := JsonInt(Item, 'codigo');
      if codigo <= 0 then
        Continue;
      try
        TransmitirNFCe(codigo, True);
      except
      end;
    end;
  finally
    fila.Free;
  end;
end;

constructor TThreadConsultaDFe.Create;
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FIntervaloMS := 60 * 60 * 1000;
end;

procedure TThreadConsultaDFe.Execute;
var
  Retorno: TJSONObject;
  conexao: TConexao;
  I: Integer;
begin
  while not Terminated do
  begin
    Retorno := nil;
    conexao := TConexao.Create('TThreadConsultaDFe');
    try
      if DFeHabilitado(conexao) then
      begin
        ManifestarDFePendentesAutomatico;
        Retorno := ConsultarDFeSefaz('');
      end;
    except
    end;
    conexao.Free;
    Retorno.Free;
    for I := 1 to FIntervaloMS div 1000 do
    begin
      if Terminated then
        Break;
      Sleep(1000);
    end;
  end;
end;

constructor TThreadStatusServicoNFe.Create;
begin
  inherited Create(False);
  FreeOnTerminate := False;
  FIntervaloMS := 5 * 60 * 1000;
end;

function TThreadStatusServicoNFe.ProximoIntervalo(const Status
  : TJSONObject): Integer;
var
  StatusServico: TJSONObject;
  cStat: Integer;
  motivo: String;
begin
  Result := 60 * 1000;
  if not Assigned(Status) then
    Exit;
  if Assigned(Status.GetValue('erro')) then
  begin
    Result := 30 * 1000;
    Exit;
  end;
  StatusServico := Status.GetValue('status_servico') as TJSONObject;
  if not Assigned(StatusServico) then
    Exit;
  cStat := StrToIntDef(StatusServico.GetValue('cStat').Value, 0);
  motivo := LowerCase(StatusServico.GetValue('xMotivo').Value);
  if cStat = 107 then
    Result := 5 * 60 * 1000
  else if Pos('conting', motivo) > 0 then
    Result := 30 * 1000
  else
    Result := 60 * 1000;
end;

procedure TThreadStatusServicoNFe.AguardarIntervalo;
var
  I: Integer;
begin
  for I := 1 to FIntervaloMS div 1000 do
  begin
    if Terminated then
      Break;
    Sleep(1000);
  end;
end;

procedure TThreadStatusServicoNFe.Execute;
var
  Status: TJSONObject;
begin
  while not Terminated do
  begin
    Status := nil;
    try
      Status := ConsultarStatusServicoNFe;
      FIntervaloMS := ProximoIntervalo(Status);
    except
      FIntervaloMS := 30 * 1000;
    end;
    Status.Free;
    AguardarIntervalo;
  end;
end;

function DescricaoProdutoErro(Item: TJSONObject): String;
begin
  Result := '[' + JsonStr(Item, 'code') + '] ' + JsonStr(Item, 'name');
end;

function SomenteNumeros(const texto: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(texto) do
    if CharInSet(texto[I], ['0' .. '9']) then
      Result := Result + texto[I];
end;

function DocumentoValidoBasico(const documento: String): Boolean;
var
  numeros: String;
begin
  numeros := SomenteNumeros(documento);
  Result := Length(numeros) in [11, 14];
end;

function GTINValido(const codigo: String): Boolean;
var
  numeros: String;
  I, soma, peso, digito: Integer;
begin
  numeros := SomenteNumeros(codigo);
  Result := False;

  if not(Length(numeros) in [8, 12, 13, 14]) then
    Exit;

  soma := 0;
  peso := 3;
  for I := Length(numeros) - 1 downto 1 do
  begin
    soma := soma + (StrToIntDef(numeros[I], 0) * peso);
    if peso = 3 then
      peso := 1
    else
      peso := 3;
  end;

  digito := (10 - (soma mod 10)) mod 10;
  Result := digito = StrToIntDef(numeros[Length(numeros)], -1);
end;

procedure InicializarTotais(var Totais: TNFCeTotais);
begin
  FillChar(Totais, SizeOf(Totais), 0);
end;

function CalcularTotalProdutos(produtos: TJsonArray): Double;
var
  I: Integer;
  Item: TJSONObject;
begin
  Result := 0;
  for I := 0 to produtos.Count - 1 do
  begin
    Item := JsonObj(produtos, I);
    Result := Result + (JsonFloat(Item, 'value') * JsonFloat(Item, 'quanty'));
  end;
end;

function CalcularTotalPagamentos(pagamentos: TJsonArray): Double;
var
  I: Integer;
begin
  Result := 0;
  for I := 0 to pagamentos.Count - 1 do
    Result := Result + RoundTo(JsonFloat(JsonObj(pagamentos, I), 'valor'), -2);
end;

function ValorXML(const valor: Double; const Mascara: String): String;
var
  fs: TFormatSettings;
begin
  fs := TFormatSettings.Create;
  fs.DecimalSeparator := '.';
  Result := FormatFloat(Mascara, valor, fs);
end;

function TagsIBSCBSItemPadrao(const CST, ClassTrib: String;
  const BaseCalculo, AliqIBSUF, ValorIBSUF, AliqIBSMun, ValorIBSMun, AliqCBS,
  ValorCBS: Double): String;
var
  CSTXML, ClassTribXML: String;
begin
  CSTXML := Trim(CST);
  if CSTXML = '' then
    CSTXML := '000';
  ClassTribXML := Trim(ClassTrib);
  if ClassTribXML = '' then
    ClassTribXML := '000001';

  Result := '<IBSCBS>' + '<CST>' + CSTXML + '</CST>' + '<cClassTrib>' +
    ClassTribXML + '</cClassTrib>' + '<gIBSCBS>' + '<vBC>' +
    ValorXML(BaseCalculo, '0.00') + '</vBC>' + '<gIBSUF>' + '<pIBSUF>' +
    ValorXML(AliqIBSUF, '0.0000') + '</pIBSUF>' + '<vIBSUF>' +
    ValorXML(ValorIBSUF, '0.00') + '</vIBSUF>' + '</gIBSUF>' + '<gIBSMun>' +
    '<pIBSMun>' + ValorXML(AliqIBSMun, '0.0000') + '</pIBSMun>' + '<vIBSMun>' +
    ValorXML(ValorIBSMun, '0.00') + '</vIBSMun>' + '</gIBSMun>' + '<vIBS>' +
    ValorXML(ValorIBSUF + ValorIBSMun, '0.00') + '</vIBS>' + '<gCBS>' + '<pCBS>'
    + ValorXML(AliqCBS, '0.0000') + '</pCBS>' + '<vCBS>' +
    ValorXML(ValorCBS, '0.00') + '</vCBS>' + '</gCBS>' + '</gIBSCBS>' +
    '</IBSCBS>';
end;

function TagsIBSCBSTotalPadrao(const BaseCalculo, ValorIBSUF, ValorIBSMun,
  ValorCBS: Double): String;
begin
  Result := '<IBSCBSTot>' + '<vBCIBSCBS>' + ValorXML(BaseCalculo, '0.00') +
    '</vBCIBSCBS>' + '<gIBS>' + '<gIBSUF>' + '<vDif>0.00</vDif>' +
    '<vDevTrib>0.00</vDevTrib>' + '<vIBSUF>' + ValorXML(ValorIBSUF, '0.00') +
    '</vIBSUF>' + '</gIBSUF>' + '<gIBSMun>' + '<vDif>0.00</vDif>' +
    '<vDevTrib>0.00</vDevTrib>' + '<vIBSMun>' + ValorXML(ValorIBSMun, '0.00') +
    '</vIBSMun>' + '</gIBSMun>' + '<vIBS>' + ValorXML(ValorIBSUF + ValorIBSMun,
    '0.00') + '</vIBS>' + '<vCredPres>0.00</vCredPres>' +
    '<vCredPresCondSus>0.00</vCredPresCondSus>' + '</gIBS>' + '<gCBS>' +
    '<vDif>0.00</vDif>' + '<vDevTrib>0.00</vDevTrib>' + '<vCBS>' +
    ValorXML(ValorCBS, '0.00') + '</vCBS>' + '<vCredPres>0.00</vCredPres>' +
    '<vCredPresCondSus>0.00</vCredPresCondSus>' + '</gCBS>' + '</IBSCBSTot>';
end;

function AplicarTagsIBSCBSPadraoXML(const XML: String; produtos: TJsonArray;
  const Totais: TNFCeTotais): String;
var
  DetMatch: TMatch;
  Matches: TMatchCollection;
  I: Integer;
  DetXML, NovoDetXML, ImpostoXML, ProdXML: String;
  Item: TJSONObject;
  BaseCalculo, AliqIBSUF, ValorIBSUF, AliqIBSMun, ValorIBSMun, AliqCBS,
    ValorCBS, TotalBaseIBSCBS, TotalIBSUF, TotalIBSMun, TotalCBS: Double;
begin
  Result := XML;
  TotalBaseIBSCBS := 0;
  TotalIBSUF := 0;
  TotalIBSMun := 0;
  TotalCBS := 0;

  if Pos('<IBSCBS>', Result) = 0 then
  begin
    Matches := TRegEx.Matches(Result,
      '<(?:[A-Za-z0-9_]+:)?det\b[^>]*>.*?</(?:[A-Za-z0-9_]+:)?det>',
      [roSingleLine, roIgnoreCase]);

    for I := Matches.Count - 1 downto 0 do
    begin
      DetMatch := Matches.Item[I];
      DetXML := DetMatch.Value;
      ImpostoXML := BlocoTagXML(DetXML, 'imposto');
      if (ImpostoXML = '') or (Pos('<IBSCBS>', ImpostoXML) > 0) then
        Continue;

      ProdXML := BlocoTagXML(DetXML, 'prod');
      BaseCalculo := ValorTagXML(ProdXML, 'vProd') - ValorTagXML(ProdXML,
        'vDesc') + ValorTagXML(ProdXML, 'vFrete') + ValorTagXML(ProdXML, 'vSeg')
        + ValorTagXML(ProdXML, 'vOutro');
      if BaseCalculo < 0 then
        BaseCalculo := 0;
      if I < produtos.Count then
        Item := JsonObj(produtos, I)
      else
        Item := nil;
      AliqIBSUF := JsonFloatName(Item, 'ibsUfAliq', 'ibs_uf_aliq') *
        (Max(0, 100 - JsonFloatName(Item, 'ibsCbsPredIbs', 'ibs_cbs_pred_ibs')) / 100);
      AliqIBSMun := JsonFloatName(Item, 'ibsMunAliq', 'ibs_mun_aliq') *
        (Max(0, 100 - JsonFloatName(Item, 'ibsCbsPredIbs', 'ibs_cbs_pred_ibs')) / 100);
      AliqCBS := JsonFloatName(Item, 'cbsAliq', 'cbs_aliq') *
        (Max(0, 100 - JsonFloatName(Item, 'ibsCbsPredCbs', 'ibs_cbs_pred_cbs')) / 100);
      ValorIBSUF := RoundTo((BaseCalculo * AliqIBSUF) / 100, -2);
      ValorIBSMun := RoundTo((BaseCalculo * AliqIBSMun) / 100, -2);
      ValorCBS := RoundTo((BaseCalculo * AliqCBS) / 100, -2);
      TotalBaseIBSCBS := TotalBaseIBSCBS + BaseCalculo;
      TotalIBSUF := TotalIBSUF + ValorIBSUF;
      TotalIBSMun := TotalIBSMun + ValorIBSMun;
      TotalCBS := TotalCBS + ValorCBS;

      NovoDetXML := TRegEx.Replace(DetXML, '(</(?:[A-Za-z0-9_]+:)?imposto>)',
        TagsIBSCBSItemPadrao(JsonStrAny(Item, 'ibsCbsCst', 'ibs_cbs_cst'),
        JsonStrAny(Item, 'ibsCbsClassTrib', 'ibs_cbs_class_trib'), BaseCalculo, AliqIBSUF, ValorIBSUF,
        AliqIBSMun, ValorIBSMun, AliqCBS, ValorCBS) + '$1',
        [roSingleLine, roIgnoreCase]);
      Result := Copy(Result, 1, DetMatch.Index) + NovoDetXML +
        Copy(Result, DetMatch.Index + DetMatch.Length + 1, MaxInt);
    end;
  end;

  if TotalBaseIBSCBS = 0 then
    TotalBaseIBSCBS := Totais.ValorItens;

  if Pos('<IBSCBSTot>', Result) = 0 then
    Result := TRegEx.Replace(Result, '(</(?:[A-Za-z0-9_]+:)?ICMSTot>)',
      '$1' + TagsIBSCBSTotalPadrao(TotalBaseIBSCBS, TotalIBSUF, TotalIBSMun,
      TotalCBS), [roSingleLine, roIgnoreCase]);
end;

function RecortarDocumentoNFeXML(const XML: String): String;
var
  Match: TMatch;
  Declaracao: String;
begin
  Result := XML;
  Match := TRegEx.Match(XML,
    '<(?:[A-Za-z0-9_]+:)?NFe\b[^>]*>.*?</(?:[A-Za-z0-9_]+:)?NFe>',
    [roSingleLine, roIgnoreCase]);
  if not Match.Success then
    Exit;

  Declaracao := '';
  if TRegEx.IsMatch(XML, '^\s*<\?xml[^>]*\?>', [roSingleLine, roIgnoreCase])
  then
    Declaracao := TRegEx.Match(XML, '^\s*<\?xml[^>]*\?>',
      [roSingleLine, roIgnoreCase]).Value;

  Result := Declaracao + Match.Value;
end;

procedure AplicarTagsIBSCBSPadrao(Acbr: TACBrNFe; produtos: TJsonArray;
  const Totais: TNFCeTotais);
var
  XML: String;
begin
  XML := AplicarTagsIBSCBSPadraoXML(Acbr.NotasFiscais.Items[0].XML,
    produtos, Totais);
  XML := RecortarDocumentoNFeXML(XML);
  if XML = RecortarDocumentoNFeXML(Acbr.NotasFiscais.Items[0].XML) then
    Exit;

  Acbr.NotasFiscais.Clear;
  Acbr.NotasFiscais.LoadFromString(XML);
end;

function LerComplemento(complementos: TJsonArray): TNFCeComplemento;
var
  obj: TJSONObject;
begin
  Result.TaxaEntrega := 0;
  Result.TaxaDesconto := 0;
  Result.CPF := '';
  Result.Nome := '';

  if complementos.Count = 0 then
    Exit;

  obj := JsonObj(complementos, 0);
  Result.TaxaDesconto := JsonFloat(obj, 'discont');
  Result.TaxaEntrega := JsonFloat(obj, 'entrega') + JsonFloat(obj, 'servico');
  Result.CPF := JsonStr(obj, 'cpf');
  Result.Nome := JsonStr(obj, 'nome');
end;

function ProximoNumeroNFCe(conexao: TConexao): Integer;
var
  Qry: TFDQuery;
  NumeroGerador, NumeroPedido: Integer;
begin
  NumeroGerador := conexao.GerarID('dados_whatsapp', 'nfce_numeracao');
  NumeroPedido := 0;
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text :=
      'SELECT COALESCE(MAX(CAST(nfce_numero AS UNSIGNED)), 0) AS numero ' +
      'FROM pedido WHERE COALESCE(nfce_numero, "") <> "" ' +
      'AND COALESCE(nfce_chave, "") NOT IN ("", "CANCELADA") ' +
      'AND COALESCE(nfce_chave, "") NOT LIKE "CONTING%"';
    Qry.Open;
    NumeroPedido := Qry.FieldByName('numero').AsInteger;
  finally
    Qry.Free;
  end;

  Result := NumeroGerador;
  if NumeroPedido >= Result then
    Result := NumeroPedido + 1;

  conexao.SQL.Add('update dados_whatsapp set nfce_numeracao = :numero');
  conexao.Parametros('numero', Result);
  conexao.ExecuteSQL;
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('UPDATE geradores SET sequencial = :numero WHERE tabela = "dados_whatsapp"');
  conexao.Parametros('numero', Result);
  conexao.ExecuteSQL;
end;

function SerieNFCe(conexao: TConexao): Integer;
begin
  Result := ParametroInt(conexao, 'nfce_serie', 2);
  if Result = 0 then
    Result := 2;
end;

function PastaDocsNFCe: String;
begin
  Result := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) + 'Docs';
  Result := IncludeTrailingPathDelimiter(Result);
end;

function PastaDocsNFCeAnoMes(const chave: String): String;
var
  ChaveLimpa, Ano, Mes: String;
begin
  ChaveLimpa := SomenteNumeros(chave);
  Result := PastaDocsNFCe;
  if Length(ChaveLimpa) >= 6 then
  begin
    Ano := '20' + Copy(ChaveLimpa, 3, 2);
    Mes := Copy(ChaveLimpa, 5, 2);
    Result := IncludeTrailingPathDelimiter(Result + Ano);
    Result := IncludeTrailingPathDelimiter(Result + Mes);
  end;
  ForceDirectories(Result);
end;

function PastaDocsDFe: String;
begin
  Result := IncludeTrailingPathDelimiter(PastaDocsNFCe + 'DFE');
end;

function ArquivoXMLNFCe(const chave: String): String;
var
  ArquivoNovo, ArquivoAntigo: String;
begin
  ArquivoNovo := PastaDocsNFCeAnoMes(chave) + chave + '-nfe.xml';
  ArquivoAntigo := PastaDocsNFCe + chave + '-nfe.xml';
  if FileExists(ArquivoAntigo) and not FileExists(ArquivoNovo) then
    Result := ArquivoAntigo
  else
    Result := ArquivoNovo;
end;

function NomeComputador: String;
var
  buffer: array [0 .. MAX_COMPUTERNAME_LENGTH] of Char;
  tamanho: DWORD;
begin
  tamanho := MAX_COMPUTERNAME_LENGTH + 1;
  if GetComputerName(buffer, tamanho) then
    Result := buffer
  else
    Result := '';
end;

function GetImpressoraPadrao(conexao: TConexao): String;
var
  Qry: TFDQuery;
begin
  Result := '';
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Add
      ('select driver from impressoras where ativo = 1 and impressora_padrao = 1 limit 1');
    Qry.Open;
    if not Qry.Eof then
      Result := Qry.FieldByName('driver').AsString;
  finally
    Qry.Free;
  end;
end;

function ModeloPosPrinter(TipoImpressao: Integer): TACBrPosPrinterModelo;
begin
  Result := ppEscPosEpson;
end;

function ColunasPosPrinter(TipoImpressao: Integer): Integer;
begin
  Result := 32;
  if TipoImpressao = 1 then
    Result := 48;
end;

procedure RegistrarErroFiscal(conexao: TConexao; codigo: Integer;
  const erro: String);
begin
  try
    conexao.SQL.Clear;
    conexao.SQL.Add('INSERT INTO erro_fiscal ');
    conexao.SQL.Add('(origem, mensagem_hash, mensagem, contador) ');
    conexao.SQL.Add('VALUES (''NFCE'', SHA2(TRIM(:erro), 256), :erro, 1) ');
    conexao.SQL.Add('ON DUPLICATE KEY UPDATE ');
    conexao.SQL.Add('contador = contador + 1, ');
    conexao.SQL.Add('ultimo_em = CURRENT_TIMESTAMP, ');
    conexao.SQL.Add('mensagem = VALUES(mensagem)');
    conexao.Parametros('erro', erro);
    conexao.ExecuteSQL;
    conexao.SQL.Clear;
    conexao.SQL.Add('INSERT IGNORE INTO erro_fiscal_pedido ');
    conexao.SQL.Add('(erro_fiscal_id, pedido_id) ');
    conexao.SQL.Add('SELECT id, :pedido FROM erro_fiscal ');
    conexao.SQL.Add('WHERE origem = ''NFCE'' ');
    conexao.SQL.Add('AND mensagem_hash = SHA2(TRIM(:erro), 256)');
    conexao.Parametros('pedido', codigo);
    conexao.Parametros('erro', erro);
    conexao.ExecuteSQL;
  except
    // Mantem o registro original do erro mesmo se a tabela nova ainda nao existir.
  end;
end;

procedure RegistrarErroNFCeComConexao(conexao: TConexao; codigo: Integer;
  const erro: String);
begin
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('UPDATE pedido SET nfce_status = "ERRO", nfce_tentativas = nfce_tentativas + 1 WHERE codigo = :pedido');
  conexao.Parametros('pedido', codigo);
  conexao.ExecuteSQL;
  conexao.SQL.Clear;
  conexao.SQL.Add('INSERT INTO alerta_sistema ');
  conexao.SQL.Add('(tipo, origem, referencia_id, payload) ');
  conexao.SQL.Add('VALUES (''NFCE_ERRO'', ''SISTEMA'', :pedido, ');
  conexao.SQL.Add('JSON_OBJECT(''pedido'', :pedido, ''mensagem'', :erro))');
  conexao.Parametros('pedido', codigo);
  conexao.Parametros('erro', erro);
  conexao.ExecuteSQL;
  RegistrarErroFiscal(conexao, codigo, erro);
end;

function AmbienteNFCe(Acbr: TACBrNFe): String;
begin
  if Acbr.NotasFiscais.Items[0].NFe.Ide.tpAmb = taProducao then
    Result := '1'
  else
    Result := '2';
end;

function ExtrairChaveNFeDoTexto(const texto: String): String;
var
  Match: TMatch;
begin
  Result := '';
  Match := TRegEx.Match(texto, '\d{44}');
  if Match.Success then
    Result := Match.Value;
end;

function ChaveNFCeMontada(Acbr: TACBrNFe): String;
begin
  Result := ExtrairChaveNFeDoTexto(Acbr.NotasFiscais.Items[0].NFe.infNFe.ID);
  if Result = '' then
    Result := ExtrairChaveNFeDoTexto(Acbr.NotasFiscais.Items[0].XML);
end;

procedure ValidarRetornoAutorizacaoNFCe(const chaveEsperada, chaveRetorno,
  protocolo: String);
begin
  if Length(chaveRetorno) <> 44 then
    raise Exception.Create('Retorno da NFC-e sem chave de autorizacao valida.');

  if Trim(protocolo) = '' then
    raise Exception.Create('Retorno da NFC-e sem protocolo de autorizacao.');

  if (chaveEsperada <> '') and (chaveRetorno <> chaveEsperada) then
    raise Exception.CreateFmt
      ('Chave retornada pela SEFAZ diverge da NFC-e transmitida. Esperada: %s Retornada: %s',
      [chaveEsperada, chaveRetorno]);
end;

function ExtrairNItemDoErro(const texto: String): Integer;
var
  Match: TMatch;
begin
  Result := -1;
  Match := TRegEx.Match(texto, '\[nItem:(\d+)\]');
  if Match.Success then
    Result := StrToIntDef(Match.Groups[1].Value, -1);
end;

function MensagemErroTransmissao(Acbr: TACBrNFe; const erro: String): String;
var
  nItem: Integer;
begin
  Result := erro;
  nItem := ExtrairNItemDoErro(erro);
  if (nItem > 0) and (nItem <= Acbr.NotasFiscais.Items[0].NFe.Det.Count) then
    Result := Result + ' - ' + Acbr.NotasFiscais.Items[0].NFe.Det.Items
      [nItem - 1].Prod.xProd;
end;

function ErroSSLConexao(const erro: String): Boolean;
begin
  Result := (Pos('12030', erro) > 0) or
    (Pos('protocolo ssl incompat', LowerCase(erro)) > 0);
end;

procedure EnviarNFCeSefaz(Acbr: TACBrNFe);
begin
  try
    Acbr.Enviar('1', False, True);
  except
    on E: Exception do
    begin
      if not ErroSSLConexao(E.Message) then
        raise;
      Acbr.Configuracoes.Geral.SSLHttpLib := httpWinINet;
      Acbr.Configuracoes.WebServices.SSLType := LT_TLSv1_2;
      Acbr.Enviar('1', False, True);
    end;
  end;
end;

procedure RegistrarEmissaoNFCe(conexao: TConexao; codigo, numero: Integer;
  const chave, protocolo, ambiente: String);
begin
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('UPDATE pedido SET nfce_status = "EMITIDA", nfce_emite = 0 WHERE (codigo = :codigo or pedido_nfce = :codigo)');
  conexao.Parametros('codigo', codigo);
  conexao.ExecuteSQL;
  if (chave = 'CONTINGENCIA') or (chave = 'CONTING?NCIA') then
  begin
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('UPDATE pedido SET nfce_status = "CONTINGENCIA", nfce_emite = 0 WHERE (codigo = :codigo or pedido_nfce = :codigo)');
    conexao.Parametros('codigo', codigo);
    conexao.ExecuteSQL;
  end;
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('update pedido set nfce_hora = current_time, nfce_data = current_date, nfce_chave = :nfce_chave, nfce_protocolo = :nfce_protocolo, nfce_ambiente = :nfce_ambiente, nfce_numero = :nfce_numero, nfce_emite = 2 where (codigo = :codigo or pedido_nfce = :codigo)');
  conexao.Parametros('codigo', codigo);
  conexao.Parametros('nfce_chave', chave);
  conexao.Parametros('nfce_protocolo', protocolo);
  conexao.Parametros('nfce_ambiente', ambiente);
  conexao.Parametros('nfce_numero', numero);
  conexao.ExecuteSQL;
end;

procedure RegistrarPedidoImpressaoNFCe(conexao: TConexao; codigo: Integer);
begin
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('insert into impressao_pedido_nfce (id_pedido) values (:codigo)');
  conexao.Parametros('codigo', codigo);
  conexao.ExecuteSQL;
end;

procedure MarcarNotaSincronizadaBase(conexao: TConexao;
  const chave, caminho, path: String);
begin
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('update pedido set nfce_sinc_contabilidade = 1 where nfce_chave = :nfce_chave');
  conexao.Parametros('nfce_chave', chave);
  conexao.ExecuteSQL;
  conexao.SQL.Clear;
  conexao.SQL.Add('delete from pedido_nfce where chave = :chave');
  conexao.Parametros('chave', chave);
  conexao.ExecuteSQL;
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('insert into pedido_nfce (id,id_pedido,chave,protocolo,caminho,path) ' +
    'select :id,codigo,nfce_chave,nfce_protocolo,:caminho,:path ' +
    'from pedido where nfce_chave = :chave');
  conexao.Parametros('id', conexao.GerarID('pedido_nfce', 'id'));
  conexao.Parametros('chave', chave);
  conexao.Parametros('caminho', caminho);
  conexao.Parametros('path', path);
  conexao.ExecuteSQL;
end;

procedure RegistrarCancelamentoNFCe(conexao: TConexao;
  const chave, motivo: String);
begin
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('update pedido set nfce_chave = "CANCELADA", nfce_status = "CANCELADA", motivo_cancelamento = :motivo where nfce_chave = :chave');
  conexao.Parametros('chave', chave);
  conexao.Parametros('motivo', motivo);
  conexao.ExecuteSQL;
end;

procedure ConfigurarDANFEImpressao(Acbr: TACBrNFe; conexao: TConexao;
  codigo: Integer);
var
  impressora: TNFCeImpressora;
  PosPrinter: TACBrPosPrinter;
  DANFE: TACBrNFeDANFeESCPOS;
begin
  if codigo > 0 then
    impressora := GetImpressora(codigo, conexao)
  else
  begin
    impressora.Driver := GetImpressoraPadrao(conexao);
    impressora.TipoImpressao := 1;
  end;
  if Trim(impressora.Driver) = '' then
    raise Exception.Create('Impressora da NFC-e nao configurada.');
  PosPrinter := TACBrPosPrinter.Create(Acbr);
  PosPrinter.Modelo := ModeloPosPrinter(impressora.TipoImpressao);
  PosPrinter.PaginaDeCodigo := pc850;
  PosPrinter.ColunasFonteNormal := ColunasPosPrinter(impressora.TipoImpressao);
  PosPrinter.Porta := 'RAW:' + impressora.Driver;
  PosPrinter.Ativar;
  DANFE := TACBrNFeDANFeESCPOS.Create(Acbr);
  DANFE.PosPrinter := PosPrinter;
  DANFE.Sistema := 'Goopedir - www.goopedir.com.br';
  Acbr.DANFE := DANFE;
end;

procedure ImprimirNFCe(Acbr: TACBrNFe; conexao: TConexao; codigo: Integer);
begin
  if Acbr.NotasFiscais.Items[0].NFe.Ide.tpEmis <> teContingencia then
  begin
    ConfigurarDANFEImpressao(Acbr, conexao, codigo);
    Acbr.NotasFiscais.imprimir;
  end;
end;

function ParametroStr(conexao: TConexao; const chave: String): String;
begin
  Result := VarToStr(conexao.GetParametro(chave));
end;

function ParametroInt(conexao: TConexao; const chave: String;
  valorPadrao: Integer): Integer;
begin
  Result := StrToIntDef(ParametroStr(conexao, chave), valorPadrao);
end;

function ParametroDFe(conexao: TConexao; const chave: String): String;
var
  Qry: TFDQuery;
begin
  Qry := nil;
  Result := Trim(ParametroStr(conexao, chave));
  if Result <> '' then
    Exit;

  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Add('SELECT ' + chave + ' FROM dados_whatsapp LIMIT 1');
    Qry.Open;
    if not Qry.Eof then
      Result := Trim(Qry.FieldByName(chave).AsString);
  except
    Result := '';
  end;
  Qry.Free;
end;

function PathSchemasNFe(conexao: TConexao): String;
var
  Candidato: String;
begin
  Result := Trim(ParametroDFe(conexao, 'nfe_path_schemas'));
  if (Result <> '') and DirectoryExists(Result) then
    Exit;

  Candidato := TPath.Combine(ExtractFilePath(ParamStr(0)), 'Schemas');
  if DirectoryExists(Candidato) then
    Exit(Candidato);



  Result := '';
end;

function DFeHabilitado(conexao: TConexao): Boolean;
begin
  Result := StrToIntDef(ParametroDFe(conexao, 'utilizar_dfe'), 0) = 1;
end;

function TipoManifestacaoDFePadrao(conexao: TConexao): String;
begin
  Result := ParametroDFe(conexao, 'manifestar_dfe_tipo');
end;

procedure ConfigurarCertificado(ACBrNFe: TACBrNFe; conexao: TConexao);
begin
  ACBrNFe.Configuracoes.Certificados.NumeroSerie :=
    ParametroStr(conexao, 'certificado');
end;

procedure ConfigurarNFCe(ACBrNFe: TACBrNFe; conexao: TConexao);
begin
  ACBrNFe.Configuracoes.Geral.AtualizarXMLCancelado := True;
  ACBrNFe.Configuracoes.Geral.ModeloDF := moNFCe;
  ACBrNFe.Configuracoes.Geral.VersaoDF := ve400;
  ACBrNFe.Configuracoes.Arquivos.PathSchemas := PathSchemasNFe(conexao);
  ACBrNFe.Configuracoes.Geral.FormatoAlerta :=
    'TAG:%TAGNIVEL% ID:%ID%/%TAG%(%DESCRICAO%) - %MSG%.';
  ACBrNFe.Configuracoes.Geral.IdCSC := ParametroStr(conexao, 'id_token_scs');
  ACBrNFe.Configuracoes.Geral.CSC := ParametroStr(conexao, 'token_scs');
  ACBrNFe.Configuracoes.Geral.FormaEmissao :=
    TpcnTipoEmissao(ParametroInt(conexao, 'forma_emissao', 0));
end;

procedure ConfigurarWebServices(ACBrNFe: TACBrNFe; conexao: TConexao);
begin
  ACBrNFe.Configuracoes.WebServices.ambiente :=
    TpcnTipoAmbiente(ParametroInt(conexao, 'ambiente', 1));
  ACBrNFe.Configuracoes.WebServices.UF := ParametroStr(conexao, 'estado');
  ACBrNFe.Configuracoes.WebServices.SSLType := LT_TLSv1_2;
  ACBrNFe.Configuracoes.WebServices.AguardarConsultaRet := 15000;
  ACBrNFe.Configuracoes.WebServices.AjustaAguardaConsultaRet := True;
  ACBrNFe.Configuracoes.WebServices.TimeOut := 20000;
  ACBrNFe.Configuracoes.WebServices.QuebradeLinha := '|';
end;

procedure ConfigurarSSL(ACBrNFe: TACBrNFe);
begin
  ACBrNFe.Configuracoes.Geral.SSLLib := libWinCrypt;
  ACBrNFe.Configuracoes.Geral.SSLCryptLib := cryWinCrypt;
  ACBrNFe.Configuracoes.Geral.SSLHttpLib := httpWinHttp;
  ACBrNFe.Configuracoes.Geral.SSLXmlSignLib := xsLibXml2;
end;

procedure AlimentarIde(Acbr: TACBrNFe; conexao: TConexao;
  numeroNota, NumeroSerie: Integer);
var
  ambiente: TpcnTipoAmbiente;
begin
  with Acbr.NotasFiscais.Items[0].NFe.Ide do
  begin
    natOp := 'VENDA';
    indPag := ipVista;
    Modelo := 65;
    Serie := NumeroSerie;
    nNF := numeroNota;
    cNF := GerarCodigoDFe(nNF);
    dEmi := Now;
    dSaiEnt := Now;
    hSaiEnt := Now;
    tpNF := tnSaida;
    tpEmis := TpcnTipoEmissao(ParametroInt(conexao, 'forma_emissao', 0));

    ambiente := TpcnTipoAmbiente(ParametroInt(conexao, 'ambiente', 1));
    tpAmb := ambiente;
    Acbr.Configuracoes.WebServices.ambiente := ambiente;

    cUF := UFtoCUF(UpperCase(ParametroStr(conexao, 'estado')));
    cMunFG := ParametroInt(conexao, 'codcidade', 0);
    finNFe := fnNormal;
    tpImp := tiNFCe;
    indFinal := cfConsumidorFinal;
    indPres := pcPresencial;
    indIntermed := iiSemOperacao;
  end;
end;

procedure AlimentarEmitente(Acbr: TACBrNFe; conexao: TConexao);
var
  ok: Boolean;
begin
  with Acbr.NotasFiscais.Items[0].NFe.Emit do
  begin
    CNPJCPF := ParametroStr(conexao, 'cnpj');
    IE := ParametroStr(conexao, 'ie');
    if Length(IE) = 0 then
      IE := 'ISENTO';

    xNome := UpperCase(ParametroStr(conexao, 'razao'));
    xFant := UpperCase(ParametroStr(conexao, 'nome'));

    EnderEmit.fone := ParametroStr(conexao, 'fone');
    EnderEmit.CEP := StrToIntDef(SomenteNumeros(ParametroStr(conexao,
      'cep')), 0);
    EnderEmit.xLgr := UpperCase(ParametroStr(conexao, 'rua'));
    EnderEmit.nro := ParametroStr(conexao, 'numero');
    EnderEmit.xBairro := UpperCase(ParametroStr(conexao, 'bairro'));
    EnderEmit.cMun := ParametroInt(conexao, 'codcidade', 0);
    EnderEmit.xMun := UpperCase(ParametroStr(conexao, 'cidade'));
    EnderEmit.UF := UpperCase(ParametroStr(conexao, 'estado'));
    EnderEmit.cPais := 1058;
    EnderEmit.xPais := 'BRASIL';

    IEST := '';
    CRT := StrToCRT(ok, ParametroStr(conexao, 'tipo_empresa'));
  end;
end;

procedure AlimentarDestinatario(Acbr: TACBrNFe;
  const complemento: TNFCeComplemento);
begin
  if not DocumentoValidoBasico(complemento.CPF) then
    Exit;

  with Acbr.NotasFiscais.Items[0].NFe.Dest do
  begin
    xNome := complemento.Nome;
    CNPJCPF := SomenteNumeros(complemento.CPF);
    indIEDest := inNaoContribuinte;
  end;
end;

// procedure AlimentarProdutos(Acbr: TACBrNFe; produtos: TJsonArray;
// const complemento: TNFCeComplemento; totalNota: Double;
// var totais: TNFCeTotais);
// var
// I: Integer;
// item: TJSONObject;
// DetItem: TDetCollectionItem;
// descricaoProduto: String;
// qtde, valorUnit, valorItem, BaseIBSCBS: Double;
// cstPis, cstCofins, cstIcms, csosnIcms: Integer;
// converteOk, ok: Boolean;
// begin
// with Acbr.NotasFiscais.Items[0].NFe do
// begin
// for I := 0 to produtos.Count - 1 do
// begin
// item := JsonObj(produtos, I);
// descricaoProduto := DescricaoProdutoErro(item);
// qtde := JsonFloat(item, 'quanty');
// valorUnit := JsonFloat(item, 'value');
// valorItem := qtde * valorUnit;
//
// DetItem := Det.Add;
// with DetItem do
// begin
// Prod.CEST := '';
// Prod.CFOP := JsonStr(item, 'cfop');
// Prod.NCM := JsonStr(item, 'ncm');
// Prod.nItem := I + 1;
// Prod.cProd := JsonStr(item, 'code');
// Prod.xProd := JsonStr(item, 'name');
// Prod.EXTIPI := '';
//
// Prod.uCom := JsonStr(item, 'un');
// if Prod.uCom = '' then
// Prod.uCom := 'UN';
//
// Prod.uTrib := Prod.uCom;
// Prod.qCom := qtde;
// Prod.qTrib := qtde;
// Prod.vUnCom := valorUnit;
// Prod.vUnTrib := valorUnit;
// Prod.vProd := valorItem;
//
// if totalNota > 0 then
// begin
// Prod.vOutro := RoundTo((Prod.vProd / totalNota) *
// complemento.TaxaEntrega, -2);
// Prod.vDesc := RoundTo(((Prod.vProd + Prod.vOutro) / totalNota) *
// complemento.TaxaDesconto, -2);
// end;
//
// Prod.IndTot := itSomaTotalNFe;
//
// totais.ValorProdutos := totais.ValorProdutos + Prod.vProd;
// totais.ValorNF := totais.ValorNF +
// (Prod.vProd - Prod.vDesc + Prod.vOutro);
// totais.ValorDesconto := totais.ValorDesconto + Prod.vDesc;
// totais.ValorOutros := totais.ValorOutros + Prod.vOutro;
// totais.ValorItens := totais.ValorItens +
// (Prod.vProd - Prod.vDesc + Prod.vOutro);
//
// cstPis := StrToIntDef(JsonStr(item, 'cstpis'), 0);
// cstCofins := StrToIntDef(JsonStr(item, 'cstcofins'), 0);
// cstIcms := StrToIntDef(JsonStr(item, 'csticms'), 0);
// csosnIcms := StrToIntDef(JsonStr(item, 'csosn'), 0);
//
// with Imposto do
// begin
// vTotTrib := 0;
//
// ICMS.orig := StrToOrig(ok, '0');
// with ICMS do
// begin
// if Emit.CRT = crtRegimeNormal then
// begin
// CST := StrToCSTICMS(converteOk, FormatFloat('00', cstIcms));
// if not converteOk then
// raise EDatabaseError.CreateFmt
// ('Situacao tributaria ICMS "%s" desconhecida no produto %s.',
// [IntToStr(cstIcms), descricaoProduto]);
//
// if Imposto.ICMS.CST in [cst10, cst30, cst60, cst70, cst90] then
// Prod.CEST := JsonStr(item, 'cest');
//
// modBC := dbiValorOperacao;
// if CST = cst60 then
// vBC := 0
// else
// vBC := valorItem;
//
// pICMS := JsonFloat(item, 'icms');
// vICMS := RoundTo((vBC * pICMS) / 100, -2);
// pRedBC := 0.00;
//
// if vBC > 0 then
// begin
// totais.BaseICMS := totais.BaseICMS + vBC;
// totais.ValorICMS := totais.ValorICMS + vICMS;
// end;
// end
// else
// begin
// CSOSN := StrToCSOSNIcms(converteOk, IntToStr(csosnIcms));
// if not converteOk then
// raise EDatabaseError.CreateFmt
// ('Situacao tributaria CSOSN "%s" desconhecida no produto %s.',
// [IntToStr(csosnIcms), descricaoProduto]);
//
// if Imposto.ICMS.CSOSN in [csosn201, csosn202, csosn203, csosn500,
// csosn900] then
// Prod.CEST := JsonStr(item, 'cest');
// end;
//
// pFCP := 0;
// end;
//
// PIS.CST := StrToCSTPIS(converteOk, FormatFloat('00', cstPis));
// if not converteOk then
// raise EDatabaseError.CreateFmt
// ('Situacao tributaria do PIS "%s" desconhecida no produto %s.',
// [IntToStr(cstPis), descricaoProduto]);
//
// PIS.vBC := valorItem;
// PIS.pPIS := JsonFloat(item, 'cstpis');
// PIS.vPIS := JsonFloat(item, 'pis');
//
// COFINS.CST := StrToCSTCOFINS(converteOk,
// FormatFloat('00', cstCofins));
// if not converteOk then
// raise EDatabaseError.CreateFmt
// ('Situacao tributaria do COFINS "%s" desconhecida no produto %s.',
// [IntToStr(cstCofins), descricaoProduto]);
//
// COFINS.vBC := valorItem;
// COFINS.pCOFINS := JsonFloat(item, 'cstcofins');
// COFINS.vCOFINS := JsonFloat(item, 'cofins');
//
// totais.ValorPIS := totais.ValorPIS + PIS.vPIS;
// totais.ValorCOFINS := totais.ValorCOFINS + COFINS.vCOFINS;
// end;
// BaseIBSCBS := Prod.vProd - Prod.vDesc + Prod.vOutro;
// if BaseIBSCBS < 0 then
// BaseIBSCBS := 0;
// AlimentarIBSCBSACBr(DetItem, item, BaseIBSCBS, totais);
//
// Prod.indEscala := StrToIndEscala(ok, '0');
//
// Prod.cEAN := JsonStr(item, 'bar');
// if not GTINValido(Prod.cEAN) then
// Prod.cEAN := 'SEM GTIN';
// Prod.cEANTrib := Prod.cEAN;
// end;
// end;
// end;
// end;

procedure AlimentarProdutos(Acbr: TACBrNFe; produtos: TJsonArray;
  const complemento: TNFCeComplemento; totalNota: Double;
  var Totais: TNFCeTotais);
var
  I: Integer;
  Item: TJSONObject;
  DetItem: TDetCollectionItem;
  descricaoProduto: String;
  qtde, valorUnit, valorItem, BaseIBSCBS: Double;
  cstPis, cstCofins, cstIcms, csosnIcms: Integer;
  converteOk, ok: Boolean;
begin
  with Acbr.NotasFiscais.Items[0].NFe do
  begin
    for I := 0 to produtos.Count - 1 do
    begin
      Item := JsonObj(produtos, I);
      descricaoProduto := DescricaoProdutoErro(Item);
      qtde := JsonFloat(Item, 'quanty');
      valorUnit := JsonFloat(Item, 'value');
      valorItem := qtde * valorUnit;

      DetItem := Det.Add;
      with DetItem do
      begin
        Prod.CEST := '';
        Prod.CFOP := JsonStr(Item, 'cfop');
        Prod.NCM := JsonStr(Item, 'ncm');
        Prod.nItem := I + 1;
        Prod.cProd := JsonStr(Item, 'code');
        Prod.xProd := JsonStr(Item, 'name');
        Prod.EXTIPI := '';

        Prod.uCom := JsonStr(Item, 'un');
        if Prod.uCom = '' then
          Prod.uCom := 'UN';

        Prod.uTrib := Prod.uCom;
        Prod.qCom := qtde;
        Prod.qTrib := qtde;
        Prod.vUnCom := valorUnit;
        Prod.vUnTrib := valorUnit;
        Prod.vProd := valorItem;

        if totalNota > 0 then
        begin
          Prod.vOutro := RoundTo((Prod.vProd / totalNota) *
            complemento.TaxaEntrega, -2);
          Prod.vDesc := RoundTo(((Prod.vProd + Prod.vOutro) / totalNota) *
            complemento.TaxaDesconto, -2);
        end;

        Prod.IndTot := itSomaTotalNFe;

        Totais.ValorProdutos := Totais.ValorProdutos + Prod.vProd;
        Totais.ValorNF := Totais.ValorNF +
          (Prod.vProd - Prod.vDesc + Prod.vOutro);
        Totais.ValorDesconto := Totais.ValorDesconto + Prod.vDesc;
        Totais.ValorOutros := Totais.ValorOutros + Prod.vOutro;
        Totais.ValorItens := Totais.ValorItens +
          (Prod.vProd - Prod.vDesc + Prod.vOutro);

        cstPis := StrToIntDef(JsonStr(Item, 'cstpis'), 0);
        cstCofins := StrToIntDef(JsonStr(Item, 'cstcofins'), 0);
        cstIcms := StrToIntDef(JsonStr(Item, 'csticms'), 0);
        csosnIcms := StrToIntDef(JsonStr(Item, 'csosn'), 0);

        with Imposto do
        begin
          vTotTrib := 0;

          ICMS.orig := StrToOrig(ok, '0');
          with ICMS do
          begin
            if Emit.CRT = crtRegimeNormal then
            begin
              CST := StrToCSTICMS(converteOk, FormatFloat('00', cstIcms));
              if not converteOk then
                raise EDatabaseError.CreateFmt
                  ('Situacao tributaria ICMS "%s" desconhecida no produto %s.',
                  [IntToStr(cstIcms), descricaoProduto]);

              if Imposto.ICMS.CST in [cst10, cst30, cst60, cst70, cst90] then
                Prod.CEST := JsonStr(Item, 'cest');

              modBC := dbiValorOperacao;
              if CST = cst60 then
                vBC := 0
              else
                vBC := valorItem;

              pICMS := JsonFloat(Item, 'icms');
              vICMS := RoundTo((vBC * pICMS) / 100, -2);
              pRedBC := 0.00;

              if vBC > 0 then
              begin
                Totais.BaseICMS := Totais.BaseICMS + vBC;
                Totais.ValorICMS := Totais.ValorICMS + vICMS;
              end;
            end
            else
            begin
              CSOSN := StrToCSOSNIcms(converteOk, IntToStr(csosnIcms));
              if not converteOk then
                raise EDatabaseError.CreateFmt
                  ('Situacao tributaria CSOSN "%s" desconhecida no produto %s.',
                  [IntToStr(csosnIcms), descricaoProduto]);

              if Imposto.ICMS.CSOSN in [csosn201, csosn202, csosn203, csosn500,
                csosn900] then
                Prod.CEST := JsonStr(Item, 'cest');
            end;

            pFCP := 0;
          end;

          PIS.CST := StrToCSTPIS(converteOk, FormatFloat('00', cstPis));
          if not converteOk then
            raise EDatabaseError.CreateFmt
              ('Situacao tributaria do PIS "%s" desconhecida no produto %s.',
              [IntToStr(cstPis), descricaoProduto]);

          PIS.vBC := valorItem;
          PIS.pPIS := JsonFloat(Item, 'cstpis');
          PIS.vPIS := JsonFloat(Item, 'pis');

          COFINS.CST := StrToCSTCOFINS(converteOk,
            FormatFloat('00', cstCofins));
          if not converteOk then
            raise EDatabaseError.CreateFmt
              ('Situacao tributaria do COFINS "%s" desconhecida no produto %s.',
              [IntToStr(cstCofins), descricaoProduto]);

          COFINS.vBC := valorItem;
          COFINS.pCOFINS := JsonFloat(Item, 'cstcofins');
          COFINS.vCOFINS := JsonFloat(Item, 'cofins');

          Totais.ValorPIS := Totais.ValorPIS + PIS.vPIS;
          Totais.ValorCOFINS := Totais.ValorCOFINS + COFINS.vCOFINS;
        end;
        BaseIBSCBS := Prod.vProd - Prod.vDesc + Prod.vOutro;
        if BaseIBSCBS < 0 then
          BaseIBSCBS := 0;
        vItem := BaseIBSCBS;
        AlimentarIBSCBSACBr(DetItem, Item, BaseIBSCBS, Totais);

        Prod.indEscala := StrToIndEscala(ok, '0');

        Prod.cEAN := JsonStr(Item, 'bar');
        if not GTINValido(Prod.cEAN) then
          Prod.cEAN := 'SEM GTIN';
        Prod.cEANTrib := Prod.cEAN;
      end;
    end;
  end;
end;

procedure AlimentarTotais(Acbr: TACBrNFe; const Totais: TNFCeTotais);
begin
  with Acbr.NotasFiscais.Items[0].NFe do
  begin
    Total.ICMSTot.vBC := Totais.BaseICMS;
    Total.ICMSTot.vICMS := Totais.ValorICMS;
    Total.ICMSTot.vFrete := 0.00;
    Total.ICMSTot.vSeg := 0.00;
    Total.ICMSTot.vOutro := Totais.ValorOutros;
    Total.ICMSTot.VBCST := 0.00;
    Total.ICMSTot.vST := 0.00;
    Total.ICMSTot.vII := 0.00;
    Total.ICMSTot.vIPI := 0.00;
    Total.ICMSTot.vPIS := Totais.ValorPIS;
    Total.ICMSTot.vCOFINS := Totais.ValorCOFINS;
    Total.ICMSTot.vProd := Totais.ValorProdutos;
    Total.ICMSTot.vDesc := Totais.ValorDesconto;
    Total.ICMSTot.vTotTrib := Totais.ValorTributos;
    Total.ICMSTot.vNF := Totais.ValorNF;

    Total.IBSCBSTot.vBCIBSCBS := Totais.BaseIBSCBS;
    Total.IBSCBSTot.gIBS.gIBSUFTot.vDif := 0;
    Total.IBSCBSTot.gIBS.gIBSUFTot.vDevTrib := 0;
    Total.IBSCBSTot.gIBS.gIBSUFTot.vIBSUF := Totais.ValorIBSUF;
    Total.IBSCBSTot.gIBS.gIBSMunTot.vDif := 0;
    Total.IBSCBSTot.gIBS.gIBSMunTot.vDevTrib := 0;
    Total.IBSCBSTot.gIBS.gIBSMunTot.vIBSMun := Totais.ValorIBSMun;
    Total.IBSCBSTot.gIBS.vIBS := Totais.ValorIBSUF + Totais.ValorIBSMun;
    Total.IBSCBSTot.gIBS.vCredPres := 0;
    Total.IBSCBSTot.gIBS.vCredPresCondSus := 0;
    Total.IBSCBSTot.gCBS.vDif := 0;
    Total.IBSCBSTot.gCBS.vDevTrib := 0;
    Total.IBSCBSTot.gCBS.vCBS := Totais.ValorCBS;
    Total.IBSCBSTot.gCBS.vCredPres := 0;
    Total.IBSCBSTot.gCBS.vCredPresCondSus := 0;

    Transp.modFrete := mfSemFrete;
  end;
end;

procedure AlimentarPagamentos(Acbr: TACBrNFe; pagamentos: TJsonArray;
  diferencaCentavos, valorTotal: Double; var Totais: TNFCeTotais);
var
  I: Integer;
  Item: TJSONObject;
  valorPagamento: Double;
begin
  if pagamentos.Count = 0 then
    raise Exception.Create('Nao emitir NFC-e: pedido sem pagamento.');
  with Acbr.NotasFiscais.Items[0].NFe do
  begin
    for I := 0 to pagamentos.Count - 1 do
    begin
      Item := JsonObj(pagamentos, I);
      valorPagamento := RoundTo(JsonFloat(Item, 'valor') +
        diferencaCentavos, -2);

      with pag.New do
      begin
        tPag := fpOutro;
        xPag := JsonStr(Item, 'descricao');
        vPag := valorPagamento;
      end;

      Totais.TotalPagamento := Totais.TotalPagamento + valorPagamento;
      diferencaCentavos := 0;
    end;
    if Totais.TotalPagamento <= 0 then
      raise Exception.Create('Nao emitir NFC-e: total de pagamento zerado.');
    if Totais.TotalPagamento > valorTotal then
      pag.vTroco := Totais.TotalPagamento - valorTotal;
  end;
end;

procedure AlimentarInformacoesAdicionais(Acbr: TACBrNFe);
begin
  with Acbr.NotasFiscais.Items[0].NFe do
  begin
    InfAdic.infCpl := '';
    InfAdic.infAdFisco := '';
    infIntermed.CNPJ := '';
    infIntermed.idCadIntTran := '';

    infRespTec.CNPJ := '51995523000156';
    infRespTec.xContato := 'GOOPEDIR LTDA';
    infRespTec.email := 'allan@goopedir.com';
    infRespTec.fone := '48996914811';
  end;
end;

procedure MontarNFCe(Acbr: TACBrNFe; conexao: TConexao; codigo: Integer);
var
  pagamentos: TJsonArray;
  produtos: TJsonArray;
  complementos: TJsonArray;
  complemento: TNFCeComplemento;
  Totais: TNFCeTotais;
  numeroNota, Serie: Integer;
  totalProdutos, totalPago, totalNota, diferencaCentavos: Double;
begin
  pagamentos := nil;
  produtos := nil;
  complementos := nil;
  try
    pagamentos := GetPagamento(codigo);
    produtos := GetProdutos(codigo);
    complementos := GetComplemento(codigo);
    if produtos.Count = 0 then
      raise Exception.Create('Nao emitir NFC-e: pedido sem produto.');
    if pagamentos.Count = 0 then
      raise Exception.Create('Nao emitir NFC-e: pedido sem pagamento.');
    InicializarTotais(Totais);
    complemento := LerComplemento(complementos);
    totalProdutos := CalcularTotalProdutos(produtos);
    totalPago := CalcularTotalPagamentos(pagamentos);
    totalNota := totalProdutos + complemento.TaxaEntrega;
    diferencaCentavos := ((totalProdutos + complemento.TaxaEntrega) -
      complemento.TaxaDesconto) - totalPago;
    numeroNota := ProximoNumeroNFCe(conexao);
    Serie := SerieNFCe(conexao);
    Acbr.NotasFiscais.Clear;
    Acbr.NotasFiscais.Add;
    AlimentarIde(Acbr, conexao, numeroNota, Serie);
    AlimentarEmitente(Acbr, conexao);
    AlimentarDestinatario(Acbr, complemento);
    AlimentarProdutos(Acbr, produtos, complemento, totalNota, Totais);
    AlimentarTotais(Acbr, Totais);
    AlimentarPagamentos(Acbr, pagamentos, diferencaCentavos,
      Totais.ValorItens, Totais);
    AlimentarInformacoesAdicionais(Acbr);
    Acbr.NotasFiscais.GerarNFe;
    if (Totais.BaseIBSCBS > 0) and (Pos('<IBSCBS>', Acbr.NotasFiscais.Items[0].XML) = 0) then
      raise Exception.CreateFmt('ACBr nao gerou IBSCBS no XML. Primeiro item: CST=%s cClassTrib=%s vBC=%.2f IBS=%.2f CBS=%.2f.',
        [JsonStrAny(JsonObj(produtos, 0), 'ibsCbsCst', 'ibs_cbs_cst'),
         JsonStrAny(JsonObj(produtos, 0), 'ibsCbsClassTrib', 'ibs_cbs_class_trib'),
         Totais.BaseIBSCBS, Totais.ValorIBSUF + Totais.ValorIBSMun, Totais.ValorCBS]);
  finally
    if Assigned(complementos) then
      complementos.Free;
    if Assigned(produtos) then
      produtos.Free;
    if Assigned(pagamentos) then
      pagamentos.Free;
  end;
end;

function GerarNFCe(codigo: Integer): String;
var
  Acbr: TACBrNFe;
  conexao: TConexao;
begin
  Acbr := nil;
  conexao := TConexao.Create('GerarNFCe');
  try
    try
      Acbr := CreateAcbrNf(conexao);
      MontarNFCe(Acbr, conexao, codigo);
      Result := Acbr.NotasFiscais.Items[0].XML;
    except
      on E: Exception do
      begin
        try
          RegistrarErroNFCeComConexao(conexao, codigo, E.Message);
        except
        end;
        raise;
      end;
    end;
  finally
    conexao.Free;
    Acbr.Free;
  end;
end;

function TransmitirNFCe(codigo: Integer; imprimir: Boolean): String;
var
  Acbr: TACBrNFe;
  conexao: TConexao;
  chave, chaveEsperada, protocolo, ambiente, erro, motivoStatus: String;
  numero: Integer;
begin
  Acbr := nil;
  conexao := TConexao.Create('TransmitirNFCe');
  try
    try
      Acbr := CreateAcbrNf(conexao);
      MontarNFCe(Acbr, conexao, codigo);
      ambiente := AmbienteNFCe(Acbr);
      numero := Acbr.NotasFiscais.Items[0].NFe.Ide.nNF;
      chaveEsperada := ChaveNFCeMontada(Acbr);
      if Acbr.NotasFiscais.Items[0].NFe.Ide.tpEmis = teContingencia then
      begin
        chave := 'CONTINGENCIA';
        protocolo := '0';
        RegistrarEmissaoNFCe(conexao, codigo, numero, chave, protocolo,
          ambiente);
        RegistrarPedidoImpressaoNFCe(conexao, codigo);
        Result := chave;
        Exit;
      end;
      erro := '';
      if not StatusServicoNFeDisponivel(motivoStatus) then
        raise Exception.Create(motivoStatus);
      try
        EnviarNFCeSefaz(Acbr);
      except
        on E: Exception do
        begin
          erro := MensagemErroTransmissao(Acbr, E.Message);
          if Pos('Duplicidade de NF-e', erro) = 0 then
            raise Exception.Create(erro);
        end;
      end;
      if Pos('Duplicidade de NF-e', erro) > 0 then
      begin
        chave := ExtrairChaveNFeDoTexto(erro);
        if chave = '' then
          raise Exception.Create(erro);
        Acbr.NotasFiscais.Clear;
        Acbr.WebServices.Consulta.NFeChave := chave;
        Acbr.WebServices.Consulta.Executar;
        protocolo := Acbr.WebServices.Consulta.protocolo;
        ValidarRetornoAutorizacaoNFCe(chaveEsperada, chave, protocolo);
        RegistrarEmissaoNFCe(conexao, codigo, numero, chave, protocolo,
          ambiente);
        RegistrarPedidoImpressaoNFCe(conexao, codigo);
        Result := chave;
        Exit;
      end;
      chave := Acbr.NotasFiscais.Items[0].NFe.procNFe.chNFe;
      protocolo := Acbr.NotasFiscais.Items[0].NFe.procNFe.nProt;
      ValidarRetornoAutorizacaoNFCe(chaveEsperada, chave, protocolo);
      Acbr.Configuracoes.Arquivos.PathSalvar := PastaDocsNFCeAnoMes(chave);
      Acbr.NotasFiscais.Items[0].GravarXML;
      RegistrarEmissaoNFCe(conexao, codigo, numero, chave, protocolo, ambiente);
      if imprimir then
        ImprimirNFCe(Acbr, conexao, codigo);
      try
        EnviarNotaFiscalNFCe(chave, ArquivoXMLNFCe(chave));
      except
      end;

      EmailFiscal(chave, '');
      RegistrarPedidoImpressaoNFCe(conexao, codigo);
      Result := chave;
    except
      on E: Exception do
      begin
        try
          RegistrarErroNFCeComConexao(conexao, codigo, E.Message);
        except
        end;
      end;
    end;
  finally
    conexao.Free;
    Acbr.Free;
  end;
end;

procedure ImprimirNFCeChave(const chave: String);
var
  Acbr: TACBrNFe;
  conexao: TConexao;
  arquivo: String;
begin
  Acbr := nil;
  conexao := TConexao.Create('ImprimirNFCeChave');
  try
    Acbr := CreateAcbrNf(conexao);
    arquivo := ArquivoXMLNFCe(chave);
    if not FileExists(arquivo) then
      raise Exception.Create('XML da NFC-e nao encontrado: ' + arquivo);
    Acbr.NotasFiscais.Clear;
    Acbr.NotasFiscais.LoadFromFile(arquivo);
    ConfigurarDANFEImpressao(Acbr, conexao, 0);
    Acbr.NotasFiscais.imprimir;
  finally
    conexao.Free;
    Acbr.Free;
  end;
end;

procedure EnviarNotaFiscalNFCe(const chave, caminho: String);
var
  Acbr: TACBrNFe;
  conexao: TConexao;
  RESTClient: TRESTClient;
  RESTRequest: TRESTRequest;
  RESTResponse: TRESTResponse;
  Param: TRESTRequestParameter;
  ResponseJSON: TJSONObject;
  arquivoRemoto: String;
begin
  if not FileExists(caminho) then
    raise Exception.Create('XML da NFC-e nao encontrado: ' + caminho);
  Acbr := nil;
  conexao := TConexao.Create('EnviarNotaFiscalNFCe');
  RESTClient := TRESTClient.Create('https://nfce.goopedir.com/gravar.php');
  RESTRequest := TRESTRequest.Create(nil);
  RESTResponse := TRESTResponse.Create(nil);
  try
    Acbr := CreateAcbrNf(conexao);
    Acbr.NotasFiscais.Clear;
    Acbr.NotasFiscais.LoadFromFile(caminho, False);
    RESTRequest.Client := RESTClient;
    RESTRequest.Response := RESTResponse;
    RESTRequest.Method := rmPOST;
    RESTRequest.TimeOut := 60 * 1000;
    RESTRequest.Params.AddItem('ambiente', ParametroStr(conexao, 'ambiente'),
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.Params.AddItem('cnpj', ParametroStr(conexao, 'cnpj'),
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.Params.AddItem('data', FormatDateTime('yyyy-mm-dd',
      Acbr.NotasFiscais.Items[0].NFe.Ide.dEmi),
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.Params.AddItem('hora', FormatDateTime('hh:nn:ss',
      Acbr.NotasFiscais.Items[0].NFe.Ide.dEmi),
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.Params.AddItem('valor',
      FloatToStrF(Acbr.NotasFiscais.Items[0].NFe.Total.ICMSTot.vNF, ffFixed, 15,
      2), TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.Params.AddItem('chaveNFCe', chave,
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.Params.AddItem('name', NomeComputador,
      TRESTRequestParameterKind.pkGETorPOST);
    Param := RESTRequest.Params.AddItem;
    Param.Name := 'arquivoNFCe';
    Param.Value := caminho;
    Param.ContentType := 'application/xml';
    Param.Kind := pkFile;
    RESTRequest.Execute;
    if RESTResponse.StatusCode <> 200 then
      raise Exception.Create('Erro ao enviar nota fiscal: ' +
        RESTResponse.StatusText);
    ResponseJSON := TJSONObject.ParseJSONValue(RESTResponse.Content)
      as TJSONObject;
    try
      if not Assigned(ResponseJSON) then
        raise Exception.Create('Resposta inesperada ao enviar NFC-e.');
      if Assigned(ResponseJSON.GetValue('success')) then
      begin
        arquivoRemoto := ResponseJSON.GetValue('file').Value;
        MarcarNotaSincronizadaBase(conexao, chave, arquivoRemoto, caminho);
      end
      else if Assigned(ResponseJSON.GetValue('error')) then
      begin
        if ResponseJSON.GetValue('error').Value = 'J? existe uma nota fiscal com esta chave para o CNPJ informado.'
        then
        begin
          arquivoRemoto := '';
          if Assigned(ResponseJSON.GetValue('file')) then
            arquivoRemoto := ResponseJSON.GetValue('file').Value;
          MarcarNotaSincronizadaBase(conexao, chave, arquivoRemoto, caminho);
        end
        else
          raise Exception.Create('Erro ao enviar NFC-e: ' +
            ResponseJSON.GetValue('error').Value);
      end
      else
        raise Exception.Create('Resposta inesperada ao enviar NFC-e.');
    finally
      ResponseJSON.Free;
    end;
  finally
    RESTResponse.Free;
    RESTRequest.Free;
    RESTClient.Free;
    conexao.Free;
    Acbr.Free;
  end;
end;

procedure DeletarNFCeBase(const chave: String);
var
  conexao: TConexao;
  RESTClient: TRESTClient;
  RESTRequest: TRESTRequest;
  RESTResponse: TRESTResponse;
begin
  conexao := TConexao.Create('DeletarNFCeBase');
  RESTClient := TRESTClient.Create('https://nfce.goopedir.com/deletar.php');
  RESTRequest := TRESTRequest.Create(nil);
  RESTResponse := TRESTResponse.Create(nil);
  try
    RESTRequest.Client := RESTClient;
    RESTRequest.Response := RESTResponse;
    RESTRequest.Method := rmPOST;
    RESTRequest.AddParameter('cnpj', ParametroStr(conexao, 'cnpj'),
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.AddParameter('chaveNFCe', chave,
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.Execute;
  finally
    RESTResponse.Free;
    RESTRequest.Free;
    RESTClient.Free;
    conexao.Free;
  end;
end;

function HtmlEscapeNFCe(const valor: String): String;
begin
  Result := StringReplace(valor, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

procedure CarregarDadosEmailNFCe(conexao: TConexao; const chave: String;
  out arquivoLocal, linkXml, empresa, cliente, pedido, numero, protocolo,
  dataPedido, horaPedido, statusNota: String; out totalNota: Double);
var
  Qry: TFDQuery;
begin
  arquivoLocal := ArquivoXMLNFCe(chave);
  linkXml := '';
  empresa := '';
  cliente := '';
  pedido := '';
  numero := '';
  protocolo := '';
  dataPedido := '';
  horaPedido := '';
  statusNota := '';
  totalNota := 0;

  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Add('SELECT p.codigo, p.codigo_pedido_dia, p.nfce_numero,');
    Qry.SQL.Add('p.nfce_protocolo, p.nfce_data, p.nfce_hora,');
    Qry.SQL.Add('p.data_pedido, p.hora_pedido, p.valor_total_pedido,');
    Qry.SQL.Add('p.nfce_status, p.nome as nome_pedido, c.nome as cliente,');
    Qry.SQL.Add('pn.caminho, pn.path');
    Qry.SQL.Add('FROM pedido p');
    Qry.SQL.Add('LEFT JOIN cliente c ON c.codigo = p.codigo_cliente');
    Qry.SQL.Add
      ('LEFT JOIN pedido_nfce pn ON pn.id_pedido = p.codigo OR pn.chave = p.nfce_chave');
    Qry.SQL.Add('WHERE p.nfce_chave = :chave OR pn.chave = :chave');
    Qry.SQL.Add('ORDER BY p.codigo DESC LIMIT 1');
    Qry.ParamByName('chave').AsString := chave;
    Qry.Open;
    if not Qry.Eof then
    begin
      pedido := Qry.FieldByName('codigo').AsString;
      numero := Qry.FieldByName('nfce_numero').AsString;
      protocolo := Qry.FieldByName('nfce_protocolo').AsString;
      if not Qry.FieldByName('nfce_data').IsNull then
        dataPedido := FormatDateTime('dd/mm/yyyy', Qry.FieldByName('nfce_data')
          .AsDateTime)
      else if not Qry.FieldByName('data_pedido').IsNull then
        dataPedido := FormatDateTime('dd/mm/yyyy',
          Qry.FieldByName('data_pedido').AsDateTime);
      if not Qry.FieldByName('nfce_hora').IsNull then
        horaPedido := FormatDateTime('hh:nn:ss', Qry.FieldByName('nfce_hora')
          .AsDateTime)
      else if not Qry.FieldByName('hora_pedido').IsNull then
        horaPedido := FormatDateTime('hh:nn:ss', Qry.FieldByName('hora_pedido')
          .AsDateTime);
      totalNota := Qry.FieldByName('valor_total_pedido').AsFloat;
      statusNota := Qry.FieldByName('nfce_status').AsString;
      cliente := Qry.FieldByName('nome_pedido').AsString;
      if Trim(cliente) = '' then
        cliente := Qry.FieldByName('cliente').AsString;
      if Trim(cliente) = '' then
        cliente := 'Venda';
      linkXml := Qry.FieldByName('caminho').AsString;
      if (not FileExists(arquivoLocal)) and
        FileExists(Qry.FieldByName('path').AsString) then
        arquivoLocal := Qry.FieldByName('path').AsString;
    end;
  finally
    Qry.Free;
  end;
end;

procedure EnviarEmailNFCe(const chave, emailDestino: String);
var
  conexao: TConexao;
  Acbr: TACBrNFe;
  Mail: TACBrMail;
  arquivo: String;
  remetente, senha, smtp, empresa, cliente, pedido, numero, protocolo,
    dataPedido, horaPedido, statusNota, linkXml, BotaoXML: String;
  dataHoraEmissao: TDateTime;
  totalNota: Double;
  Porta: Integer;
  XMLLocal: Boolean;
begin
  if Trim(chave) = '' then
    raise Exception.Create('Chave da NFC-e nao informada.');
  if Trim(emailDestino) = '' then
    raise Exception.Create('E-mail de destino nao informado.');

  conexao := TConexao.Create('EnviarEmailNFCe');
  Acbr := nil;
  Mail := nil;
  try
    CarregarDadosEmailNFCe(conexao, chave, arquivo, linkXml, empresa, cliente,
      pedido, numero, protocolo, dataPedido, horaPedido, statusNota, totalNota);
    XMLLocal := FileExists(arquivo);
    if (not XMLLocal) and (Trim(linkXml) = '') then
      raise Exception.Create
        ('XML da NFC-e nao encontrado na maquina e sem link de upload em pedido_nfce: '
        + arquivo);

    remetente := ParametroStrPadrao(conexao, 'email_nfce',
      'contabilidade@goopedir.com');
    senha := ParametroStrPadrao(conexao, 'senha_email_nfce', 'Goopedir@2024');
    smtp := ParametroStrPadrao(conexao, 'smtp_nfce', 'smtp.hostinger.com');
    Porta := ParametroInt(conexao, 'porta_smtp_nfce', 465);
    if remetente = '' then
      raise Exception.Create('E-mail remetente da NFC-e nao configurado.');
    if senha = '' then
      raise Exception.Create('Senha do e-mail da NFC-e nao configurada.');

    if XMLLocal then
    begin
      Acbr := CreateAcbrNf(conexao);
      Acbr.NotasFiscais.Clear;
      Acbr.NotasFiscais.LoadFromFile(arquivo, False);
      empresa := Acbr.NotasFiscais.Items[0].NFe.Emit.xNome;
      dataHoraEmissao := Acbr.NotasFiscais.Items[0].NFe.Ide.dEmi;
      if dataPedido = '' then
        dataPedido := FormatDateTime('dd/mm/yyyy', dataHoraEmissao);
      if horaPedido = '' then
        horaPedido := FormatDateTime('hh:nn:ss', dataHoraEmissao);
      if totalNota = 0 then
        totalNota := Acbr.NotasFiscais.Items[0].NFe.Total.ICMSTot.vNF;
    end;
    if empresa = '' then
      empresa := ParametroStrPadrao(conexao, 'nome_empresa', 'Goopedir');
    if statusNota = '' then
      statusNota := 'EMITIDA';
    if linkXml <> '' then
      BotaoXML := '<p style="margin:24px 0;"><a href="' +
        HtmlEscapeNFCe(linkXml) +
        '" style="background:#1f7aec;color:#fff;text-decoration:none;padding:12px 18px;border-radius:6px;display:inline-block;font-weight:600;">Baixar XML da NFC-e</a></p>'
    else
      BotaoXML := '';

    Mail := TACBrMail.Create(nil);
    Mail.Host := smtp;
    Mail.Port := IntToStr(Porta);
    Mail.Username := remetente;
    Mail.Password := senha;
    Mail.From := remetente;
    Mail.FromName := 'Goopedir';
    Mail.SetTLS := False;
    Mail.SetSSL := True;
    Mail.IsHTML := True;
    Mail.Subject := 'NFC-e ' + empresa + ' - Pedido ' + pedido;
    Mail.Body.Text :=
      '<div style="margin:0;padding:0;background:#f4f6f8;font-family:Arial,Helvetica,sans-serif;color:#1f2937;">'
      + '<div style="max-width:680px;margin:0 auto;padding:28px 16px;">' +
      '<div style="background:#ffffff;border:1px solid #e5e7eb;border-radius:10px;overflow:hidden;">'
      + '<div style="background:#111827;color:#ffffff;padding:22px 26px;">' +
      '<div style="font-size:13px;letter-spacing:.08em;text-transform:uppercase;color:#9ca3af;">NFC-e</div>'
      + '<h1 style="font-size:22px;line-height:1.3;margin:8px 0 0;">Sua nota fiscal esta disponivel</h1>'
      + '</div>' + '<div style="padding:24px 26px;">' +
      '<p style="font-size:15px;line-height:1.6;margin:0 0 18px;">Ola, ' +
      HtmlEscapeNFCe(cliente) +
      '. Seguem os dados da NFC-e emitida pela <strong>' +
      HtmlEscapeNFCe(empresa) + '</strong>.</p>' +
      '<table style="width:100%;border-collapse:collapse;margin:18px 0;background:#f9fafb;border-radius:8px;overflow:hidden;">'
      + '<tr><td style="padding:10px 12px;color:#6b7280;">Pedido</td><td style="padding:10px 12px;text-align:right;font-weight:600;">'
      + HtmlEscapeNFCe(pedido) + '</td></tr>' +
      '<tr><td style="padding:10px 12px;color:#6b7280;">Numero NFC-e</td><td style="padding:10px 12px;text-align:right;font-weight:600;">'
      + HtmlEscapeNFCe(numero) + '</td></tr>' +
      '<tr><td style="padding:10px 12px;color:#6b7280;">Emissao</td><td style="padding:10px 12px;text-align:right;font-weight:600;">'
      + HtmlEscapeNFCe(Trim(dataPedido + ' ' + horaPedido)) + '</td></tr>' +
      '<tr><td style="padding:10px 12px;color:#6b7280;">Status</td><td style="padding:10px 12px;text-align:right;font-weight:600;">'
      + HtmlEscapeNFCe(statusNota) + '</td></tr>' +
      '<tr><td style="padding:10px 12px;color:#6b7280;">Protocolo</td><td style="padding:10px 12px;text-align:right;font-weight:600;">'
      + HtmlEscapeNFCe(protocolo) + '</td></tr>' +
      '<tr><td style="padding:10px 12px;color:#6b7280;">Total</td><td style="padding:10px 12px;text-align:right;font-size:18px;font-weight:700;color:#111827;">R$ '
      + FormatFloat('#,##0.00', totalNota) + '</td></tr>' + '</table>' +
      '<div style="font-size:12px;line-height:1.5;color:#6b7280;word-break:break-all;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px;padding:12px;">'
      + '<strong>Chave de acesso:</strong><br>' + HtmlEscapeNFCe(chave) +
      '</div>' + BotaoXML +
      '<p style="font-size:13px;color:#6b7280;margin:22px 0 0;">' +
      'Quando o XML esta disponivel nesta maquina ele segue anexado. Caso contrario, use o link acima para baixar o arquivo ja enviado ao servidor.'
      + '</p></div></div>' +
      '<p style="text-align:center;font-size:12px;color:#9ca3af;margin:18px 0 0;">Goopedir - www.goopedir.com.br</p>'
      + '</div></div>';
    Mail.AddAddress(emailDestino);
    if XMLLocal then
      Mail.AddAttachment(arquivo);
    Mail.Send;
  finally
    Mail.Free;
    Acbr.Free;
    conexao.Free;
  end;
end;

procedure IniciarThreadEmissaoNFCe;
begin
  if Assigned(ThreadEmissaoNFCe) then
    Exit;
  ThreadEmissaoNFCe := TThreadEmissaoNFCe.Create;
end;

procedure PararThreadEmissaoNFCe;
begin
  if not Assigned(ThreadEmissaoNFCe) then
    Exit;
  ThreadEmissaoNFCe.Terminate;
  ThreadEmissaoNFCe.WaitFor;
  FreeAndNil(ThreadEmissaoNFCe);
end;

procedure IniciarThreadConsultaDFe;
var
  conexao: TConexao;
begin
  if Assigned(ThreadConsultaDFe) then
    Exit;

  conexao := TConexao.Create('IniciarThreadConsultaDFe');
  try
    if not DFeHabilitado(conexao) then
      Exit;
  finally
    conexao.Free;
  end;

  ThreadConsultaDFe := TThreadConsultaDFe.Create;
end;

procedure PararThreadConsultaDFe;
begin
  if not Assigned(ThreadConsultaDFe) then
    Exit;
  ThreadConsultaDFe.Terminate;
  ThreadConsultaDFe.WaitFor;
  FreeAndNil(ThreadConsultaDFe);
end;

procedure IniciarThreadStatusServicoNFe;
begin
  if Assigned(ThreadStatusServicoNFe) then
    Exit;
  ThreadStatusServicoNFe := TThreadStatusServicoNFe.Create;
end;

procedure PararThreadStatusServicoNFe;
begin
  if not Assigned(ThreadStatusServicoNFe) then
    Exit;
  ThreadStatusServicoNFe.Terminate;
  ThreadStatusServicoNFe.WaitFor;
  FreeAndNil(ThreadStatusServicoNFe);
end;

function CancelarNFCe(const chave, motivo: String): String;
var
  Acbr: TACBrNFe;
  conexao: TConexao;
  arquivo: String;
begin
  if Trim(chave) = '' then
    raise Exception.Create('Chave da NFC-e nao informada.');
  if Length(Trim(motivo)) < 15 then
    raise Exception.Create
      ('Motivo do cancelamento deve ter no minimo 15 caracteres.');
  Acbr := nil;
  conexao := TConexao.Create('CancelarNFCe');
  try
    Acbr := CreateAcbrNf(conexao);
    arquivo := ArquivoXMLNFCe(chave);
    if not FileExists(arquivo) then
      raise Exception.Create('XML da NFC-e nao encontrado: ' + arquivo);
    Acbr.NotasFiscais.Clear;
    Acbr.NotasFiscais.LoadFromFile(arquivo);
    Acbr.EventoNFe.Evento.Clear;
    Acbr.EventoNFe.idLote := 1;
    with Acbr.EventoNFe.Evento.Add do
    begin
      infEvento.chNFe := chave;
      infEvento.CNPJ := SomenteNumeros(ParametroStr(conexao, 'cnpj'));
      infEvento.dhEvento := Now;
      infEvento.tpEvento := teCancelamento;
      infEvento.nSeqEvento := 1;
      infEvento.detEvento.xJust := motivo;
    end;
    Acbr.EnviarEvento(1);
    Result := Acbr.WebServices.EnvEvento.EventoRetorno.retEvento.Items[0]
      .RetInfEvento.nProt;
    RegistrarCancelamentoNFCe(conexao, chave, motivo);
    try
      DeletarNFCeBase(chave);
    except
    end;
  finally
    conexao.Free;
    Acbr.Free;
  end;
end;

procedure RegistrarErroNFCe(codigo: Integer; const erro: String);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('RegistrarErroNFCe');
  try
    RegistrarErroNFCeComConexao(conexao, codigo, erro);
  finally
    conexao.Free;
  end;
end;

function GetPagamento(codigo: Integer): TJsonArray;
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');
  try
    conexao.SQL.Add
      ('SELECT tipo_pagamento.descricao, TRUNCATE(caixa_movimento.valor, 2) as valor FROM caixa_movimento');
    conexao.SQL.Add
      ('join tipo_pagamento on tipo_pagamento.codigo = caixa_movimento.id_tipo_pagamento');
    conexao.SQL.Add
      ('where id_pedido = :codigo and (caixa_movimento.tipo = 1 or caixa_movimento.tipo = -999)');
    conexao.Parametros('codigo', codigo);
    Result := conexao.ConsultaSQL;
  finally
    conexao.Free;
  end;
end;

function GetProdutos(codigo: Integer): TJsonArray;
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');
  try
    // conexao.SQL.Add('SELECT upper(produto.nome_produto) as name, produto.codigo_barra as bar, produto.codigo_interno as code, ');
    // conexao.SQL.Add('TRUNCATE((pedido_produtos.valor_total / pedido_produtos.quantidade), 2) as value,');
    // conexao.SQL.Add('pedido_produtos.quantidade as quanty, un,ncm,cest,cfop,cstipi,csticms,cstpis,cstcofins,csosn,icms,ipi,pis,cofins,frete,');
    // conexao.SQL.Add('(select group_concat(upper(pedido_produto_sap.descricao)) from pedido_produto_sap where pedido_produto_sap.codigo_pedido_produto = pedido_produtos.codigo and pedido_produto_sap.valor > 0) as additional');
    // conexao.SQL.Add('FROM pedido');
    // conexao.SQL.Add('join pedido_produtos on pedido_produtos.codigo_pedido = pedido.codigo');
    // conexao.SQL.Add('join produto on produto.codigo = pedido_produtos.codigo_produto');
    // conexao.SQL.Add('where pedido.codigo = :codigo or pedido.pedido_nfce = :codigo');
    conexao.SQL.Add('SELECT *');
    conexao.SQL.Add('FROM (');
    conexao.SQL.Add('    SELECT ');
    conexao.SQL.Add('        UPPER(p.nome_produto) AS name,');
    conexao.SQL.Add('        p.codigo_barra AS bar,');
    conexao.SQL.Add('        p.codigo_interno AS code,');
    conexao.SQL.Add
      ('        TRUNCATE((pp.valor_total / pp.quantidade), 2) AS value,');
    conexao.SQL.Add('        pp.quantidade AS quanty,');
    conexao.SQL.Add
      ('        p.un,p.ncm,p.cest,p.cfop,p.cstipi,p.csticms,p.cstpis,p.cstcofins,');
    conexao.SQL.Add('        p.csosn,p.icms,p.ipi,p.pis,p.cofins,p.frete,');
    conexao.SQL.Add
      ('        p.ibs_cbs_cst AS ibsCbsCst,p.ibs_cbs_class_trib AS ibsCbsClassTrib,p.ibs_uf_aliq AS ibsUfAliq,p.ibs_mun_aliq AS ibsMunAliq,p.cbs_aliq AS cbsAliq,');
    conexao.SQL.Add
      ('        COALESCE(fct.pred_ibs, 0) AS ibsCbsPredIbs, COALESCE(fct.pred_cbs, 0) AS ibsCbsPredCbs,');
    conexao.SQL.Add('        (');
    conexao.SQL.Add('            SELECT GROUP_CONCAT(UPPER(sap.descricao))');
    conexao.SQL.Add('            FROM pedido_produto_sap sap');
    conexao.SQL.Add('            WHERE sap.codigo_pedido_produto = pp.codigo');
    conexao.SQL.Add('              AND sap.valor > 0');
    conexao.SQL.Add('        ) AS additional');
    conexao.SQL.Add('    FROM pedido pe');
    conexao.SQL.Add
      ('    JOIN pedido_produtos pp ON pp.codigo_pedido = pe.codigo');
    conexao.SQL.Add('    JOIN produto p ON p.codigo = pp.codigo_produto');
    conexao.SQL.Add
      ('    LEFT JOIN fiscal_ibs_cbs_class_trib fct ON fct.cclass_trib = p.ibs_cbs_class_trib');
    conexao.SQL.Add
      ('    WHERE (pe.codigo = :codigo OR pe.pedido_nfce = :codigo)');
    conexao.SQL.Add('      AND NOT EXISTS (');
    conexao.SQL.Add('          SELECT 1');
    conexao.SQL.Add('          FROM produto_combo_config pcc');
    conexao.SQL.Add
      ('          JOIN produto_combo_item pci ON pci.combo_config_id = pcc.id');
    conexao.SQL.Add('          WHERE pcc.produto_combo_id = p.codigo');
    conexao.SQL.Add('            AND pcc.status = "ATIVO"');
    conexao.SQL.Add('      )');
    conexao.SQL.Add('    UNION ALL');
    conexao.SQL.Add('    SELECT ');
    conexao.SQL.Add('        UPPER(pi.nome_produto) AS name,');
    conexao.SQL.Add('        pi.codigo_barra AS bar,');
    conexao.SQL.Add('        pi.codigo_interno AS code,');
    conexao.SQL.Add
      ('        TRUNCATE(((pp.valor_total / pp.quantidade) * pci.ratio), 2) AS value,');
    conexao.SQL.Add('        pp.quantidade AS quanty,');
    conexao.SQL.Add
      ('        pi.un,pi.ncm,pi.cest,pi.cfop,pi.cstipi,pi.csticms,pi.cstpis,pi.cstcofins,');
    conexao.SQL.Add
      ('        pi.csosn,pi.icms,pi.ipi,pi.pis,pi.cofins,pi.frete,');
    conexao.SQL.Add
      ('        pi.ibs_cbs_cst AS ibsCbsCst,pi.ibs_cbs_class_trib AS ibsCbsClassTrib,pi.ibs_uf_aliq AS ibsUfAliq,pi.ibs_mun_aliq AS ibsMunAliq,pi.cbs_aliq AS cbsAliq,');
    conexao.SQL.Add
      ('        COALESCE(fcti.pred_ibs, 0) AS ibsCbsPredIbs, COALESCE(fcti.pred_cbs, 0) AS ibsCbsPredCbs,');
    conexao.SQL.Add
      ('        CONCAT("COMBO: ", UPPER(pc.nome_produto)) AS additional');
    conexao.SQL.Add('    FROM pedido pe');
    conexao.SQL.Add
      ('    JOIN pedido_produtos pp ON pp.codigo_pedido = pe.codigo');
    conexao.SQL.Add('    JOIN produto pc ON pc.codigo = pp.codigo_produto');
    conexao.SQL.Add('    JOIN produto_combo_config pcc ');
    conexao.SQL.Add('        ON pcc.produto_combo_id = pc.codigo');
    conexao.SQL.Add('       AND pcc.status = "ATIVO"');
    conexao.SQL.Add('    JOIN produto_combo_item pci ');
    conexao.SQL.Add('        ON pci.combo_config_id = pcc.id');
    conexao.SQL.Add('    JOIN produto pi ');
    conexao.SQL.Add('        ON pi.codigo = pci.produto_id');
    conexao.SQL.Add
      ('    LEFT JOIN fiscal_ibs_cbs_class_trib fcti ON fcti.cclass_trib = pi.ibs_cbs_class_trib');
    conexao.SQL.Add
      ('    WHERE (pe.codigo = :codigo OR pe.pedido_nfce = :codigo)');
    conexao.SQL.Add(') fiscal;');
    conexao.Parametros('codigo', codigo);
    Result := conexao.ConsultaSQL;
  finally
    conexao.Free;
  end;
end;

function GetComplemento(codigo: Integer): TJsonArray;
var
  conexao: TConexao;
  SQL: String;
begin
  conexao := TConexao.Create('nfce');
  try
    SQL := 'select pedido.servico, pedido.valor_desconto as discont, pedido.cpf, pedido.nome, pedido.valor_taxa_entrega as entrega, impressoras.driver';
    SQL := SQL + ' FROM pedido';
    SQL := SQL + ' left join usuario on usuario.codigo = pedido.usuario';
    SQL := SQL +
      ' left join impressoras on impressoras.codigo = usuario.impressora or impressoras.impressora_padrao = 1';
    SQL := SQL +
      ' where pedido.codigo = :codigo or pedido.pedido_nfce = :codigo order by pedido.codigo desc';
    conexao.SQL.Add(SQL);
    conexao.Parametros('codigo', codigo);
    Result := conexao.ConsultaSQL();
  finally
    conexao.Free;
  end;
end;

function CreateAcbrNf(conexao: TConexao): TACBrNFe;
begin
  Result := TACBrNFe.Create(nil);
  try
    ConfigurarSSL(Result);
    ConfigurarCertificado(Result, conexao);
    ConfigurarNFCe(Result, conexao);
    ConfigurarWebServices(Result, conexao);
  except
    Result.Free;
    raise;
  end;
end;

function AmbienteDFeTexto(ambiente: TpcnTipoAmbiente): String;
begin
  if ambiente = taProducao then
    Result := 'producao'
  else
    Result := 'homologacao';
end;

function TryDataHoraParametro(const valor: String;
  out DataHora: TDateTime): Boolean;
var
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Create;
  Fmt.DateSeparator := '-';
  Fmt.TimeSeparator := ':';
  Fmt.ShortDateFormat := 'yyyy-mm-dd';
  Fmt.LongTimeFormat := 'hh:nn:ss';
  Result := TryStrToDateTime(Trim(valor), DataHora, Fmt);
end;

procedure GravarControleDFeParametro(conexao: TConexao;
  const UltimoNSU: String);
begin
  conexao.SalvarParametro(PARAM_DFE_ULTIMA_EXECUCAO,
    FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  conexao.SalvarParametro(PARAM_DFE_ULTIMO_NSU, UltimoNSU);
end;

function UltimoNSUDFe(conexao: TConexao; const CNPJ, ambiente: String): String;
var
  Dados: TFDMemTable;
  NSUParametro: String;
begin
  Result := '0';
  NSUParametro := Trim(ParametroStr(conexao, PARAM_DFE_ULTIMO_NSU));
  if NSUParametro <> '' then
  begin
    Result := NSUParametro;
    Exit;
  end;

  Dados := TFDMemTable.Create(nil);
  try
    conexao.SQL.Add
      ('SELECT ultimo_nsu, 0 as zero FROM dfe_consulta WHERE cnpj_empresa = :cnpj AND ambiente = :ambiente ORDER BY id DESC LIMIT 1');
    conexao.Parametros('cnpj', CNPJ);
    conexao.Parametros('ambiente', ambiente);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount > 0 then
      Result := Dados.FieldByName('ultimo_nsu').AsString;
  finally
    Dados.Free;
  end;
end;

function ConsultaDFeLiberada(conexao: TConexao; const CNPJ, ambiente: String;
  out Mensagem: String): Boolean;
var
  Dados: TFDMemTable;
  UltimaExecucao, ProximaExecucao: TDateTime;
  ParametroUltimaExecucao: String;
begin
  Result := True;
  Mensagem := '';
  ParametroUltimaExecucao :=
    Trim(ParametroStr(conexao, PARAM_DFE_ULTIMA_EXECUCAO));
  if TryDataHoraParametro(ParametroUltimaExecucao, UltimaExecucao) then
  begin
    ProximaExecucao := IncHour(UltimaExecucao, 1);
    Result := Now >= ProximaExecucao;
    if not Result then
      Mensagem := 'Consulta DFe bloqueada pelo parametro ate ' +
        FormatDateTime('dd/mm/yyyy hh:nn:ss', ProximaExecucao) + '.';
    Exit;
  end;

  Dados := TFDMemTable.Create(nil);
  try
    conexao.SQL.Add
      ('SELECT 0 as zero, CASE WHEN TIMESTAMP(data_consulta, hora_consulta) <= NOW() - INTERVAL 1 HOUR THEN 1 ELSE 0 END AS status '
      + 'FROM dfe_consulta WHERE cnpj_empresa = :cnpj AND ambiente = :ambiente ORDER BY id DESC LIMIT 1');
    conexao.Parametros('cnpj', CNPJ);
    conexao.Parametros('ambiente', ambiente);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount > 0 then
    begin
      Result := Dados.FieldByName('status').AsInteger = 1;
      if not Result then
        Mensagem := 'Consulta DFe ainda dentro do intervalo de 1 hora.';
    end;
  finally
    Dados.Free;
  end;
end;

function ReservarConsultaDFe(var Mensagem: String): Boolean;
begin
  Result := False;
  Mensagem := '';
  CriticalConsultaDFe.Enter;
  try
    if (ProximaConsultaDFe > 0) and (Now < ProximaConsultaDFe) then
    begin
      Mensagem := 'Consulta DFe bloqueada ate ' +
        FormatDateTime('dd/mm/yyyy hh:nn:ss', ProximaConsultaDFe) + '.';
      Exit;
    end;
    ProximaConsultaDFe := IncHour(Now, 1);
    Result := True;
  finally
    CriticalConsultaDFe.Leave;
  end;
end;

function XMLDFeEhResumo(const XML: String): Boolean;
begin
  Result := Pos('<resNFe', XML) > 0;
end;

function ManifestarDFeCiencia(Acbr: TACBrNFe;
  const CNPJ, chave: String): Boolean;
var
  cStatEvento: Integer;
begin
  Result := False;
  Acbr.EventoNFe.Evento.Clear;
  Acbr.EventoNFe.idLote := 1;
  with Acbr.EventoNFe.Evento.New do
  begin
    infEvento.cOrgao := 91;
    infEvento.chNFe := chave;
    infEvento.CNPJ := CNPJ;
    infEvento.dhEvento := Now;
    infEvento.tpEvento := teManifDestCiencia;
  end;
  try
    Acbr.EnviarEvento(1);
    cStatEvento := Acbr.WebServices.EnvEvento.EventoRetorno.retEvento.Items[0]
      .RetInfEvento.cStat;
    Result := (cStatEvento = 135) or (cStatEvento = 136) or (cStatEvento = 573);
  except
    Result := False;
  end;
end;

function TipoManifestacaoDFe(const Tipo: String; out Evento: TpcnTpEvento;
  out Descricao: String): Boolean;
var
  TipoNormalizado: String;
begin
  TipoNormalizado := LowerCase(Trim(Tipo));
  TipoNormalizado := StringReplace(TipoNormalizado, '_', '-', [rfReplaceAll]);
  Result := True;
  if (TipoNormalizado = 'ciencia') or (TipoNormalizado = 'ci?ncia') or
    (TipoNormalizado = '210210') then
  begin
    Evento := teManifDestCiencia;
    Descricao := 'Ciencia da Operacao';
  end
  else if (TipoNormalizado = 'confirmacao') or
    (TipoNormalizado = 'confirma??o') or (TipoNormalizado = '210200') then
  begin
    Evento := teManifDestConfirmacao;
    Descricao := 'Confirmacao da Operacao';
  end
  else if (TipoNormalizado = 'desconhecimento') or
    (TipoNormalizado = '210220') then
  begin
    Evento := teManifDestDesconhecimento;
    Descricao := 'Desconhecimento da Operacao';
  end
  else if (TipoNormalizado = 'nao-realizada') or
    (TipoNormalizado = 'n?o-realizada') or
    (TipoNormalizado = 'operacao-nao-realizada') or
    (TipoNormalizado = 'op-nao-realizada') or
    (TipoNormalizado = 'cancelamento') or
    (TipoNormalizado = 'cancelada') or
    (TipoNormalizado = 'cancelado') or (TipoNormalizado = '210240') then
  begin
    Evento := teManifDestOperNaoRealizada;
    Descricao := 'Operacao nao Realizada';
  end
  else
    Result := False;
end;

function BaixarXMLDFePorChave(Acbr: TACBrNFe;
  const UF, CNPJ, chave, PastaDFE: String): String;
var
  I: Integer;
  NomeArquivo: String;
  SL: TStringList;
begin
  Result := '';
  Acbr.DistribuicaoDFePorChaveNFe(UFtoCUF(UpperCase(UF)), CNPJ, chave);
  with Acbr.WebServices.DistribuicaoDFe.retDistDFeInt do
  begin
    for I := 0 to docZip.Count - 1 do
    begin
      if Trim(docZip[I].XML) = '' then
        Continue;
      if XMLDFeEhResumo(docZip[I].XML) then
        Continue;
      Result := docZip[I].XML;
      NomeArquivo := PastaDFE + 'CHAVE_' + chave + '.xml';
      SL := TStringList.Create;
      try
        SL.Text := Result;
        SL.SaveToFile(NomeArquivo);
      finally
        SL.Free;
      end;
      Break;
    end;
  end;
end;

function XMLDFeLocalPorChave(const chave: String; out caminho: String): String;
var
  SL: TStringList;
begin
  Result := '';
  caminho := PastaDocsDFe + 'CHAVE_' + chave + '.xml';
  if not FileExists(caminho) then
    Exit;
  SL := TStringList.Create;
  try
    SL.LoadFromFile(caminho);
    Result := SL.Text;
  finally
    SL.Free;
  end;
end;

function XMLDFeBancoPorChave(conexao: TConexao; const chave: String): String;
var
  Qry: TFDQuery;
begin
  Result := '';
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text := 'SELECT xml_base64 FROM dfe_documento WHERE chave = :chave '
      + 'AND tipo = "nfe" AND IFNULL(xml_base64, "") <> "" LIMIT 1';
    Qry.ParamByName('chave').AsString := chave;
    Qry.Open;
    if not Qry.Eof then
      Result := TNetEncoding.Base64.Decode(Qry.FieldByName('xml_base64')
        .AsString);
  finally
    Qry.Free;
  end;
end;

procedure GerarAlertaManifestacaoDFe(conexao: TConexao;
  const chave, Tipo, Origem, XMotivo: String; cStat: Integer);
var
  Qry: TFDQuery;
begin
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Add('INSERT INTO alerta_sistema ' +
      '(tipo, origem, referencia_id, payload) VALUES ' +
      '(''DFE'', ''SISTEMA'', NULL, JSON_OBJECT(' +
      '''tipo_alerta'', ''DFE_MANIFESTADO'', ' +
      '''mensagem'', ''Nota DFe manifestada e aguardando importacao.'', ' +
      '''chave'', :chave, ''manifestacao_tipo'', :tipo, ' +
      '''origem_manifestacao'', :origem, ''cStat'', :cstat, ' +
      '''xMotivo'', :xmotivo, ''status'', ''AGUARDANDO_IMPORTACAO''))');
    Qry.ParamByName('chave').AsString := chave;
    Qry.ParamByName('tipo').AsString := Tipo;
    Qry.ParamByName('origem').AsString := Origem;
    Qry.ParamByName('cstat').AsInteger := cStat;
    Qry.ParamByName('xmotivo').AsString := XMotivo;
    Qry.ExecSQL;
  finally
    Qry.Free;
  end;
end;

function RegistrarManifestacaoDFe(conexao: TConexao;
  const chave, Tipo, Origem, XMotivo: String; cStat: Integer): Boolean;
var
  Qry: TFDQuery;
begin
  Result := False;
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Add('UPDATE dfe_documento SET manifestada = 1, ' +
      'manifestacao_tipo = :tipo, ' +
      'manifestacao_status = ''AGUARDANDO_IMPORTACAO'', ' +
      'manifestacao_origem = :origem, manifestacao_data = NOW() ' +
      'WHERE chave = :chave');
    Qry.ParamByName('tipo').AsString := Tipo;
    Qry.ParamByName('origem').AsString := Origem;
    Qry.ParamByName('chave').AsString := chave;
    Qry.ExecSQL;
    Result := Qry.RowsAffected > 0;
  finally
    Qry.Free;
  end;

  if Result then
    GerarAlertaManifestacaoDFe(conexao, chave, Tipo, Origem, XMotivo, cStat);
end;

function ManifestarDFePorChave(const chave, Tipo, Justificativa: String;
  const Origem: String): TJSONObject;
var
  conexao: TConexao;
  Acbr: TACBrNFe;
  ChaveLimpa, CNPJConsulta, XMLCompleto, PastaDFE, DescricaoEvento,
    XMotivoEvento: String;
  Evento: TpcnTpEvento;
  cStatEvento: Integer;
begin
  Result := TJSONObject.Create;
  ChaveLimpa := SomenteNumeros(chave);
  if Length(ChaveLimpa) <> 44 then
  begin
    Result.AddPair('erro', 'Chave DFe invalida.');
    Exit;
  end;
  if not TipoManifestacaoDFe(Tipo, Evento, DescricaoEvento) then
  begin
    Result.AddPair('erro',
      'Tipo invalido. Use ciencia, confirmacao, desconhecimento ou nao-realizada.');
    Exit;
  end;
  if (Evento = teManifDestOperNaoRealizada) and
    (Length(Trim(Justificativa)) < 15) then
  begin
    Result.AddPair('erro',
      'Justificativa obrigatoria com no minimo 15 caracteres.');
    Exit;
  end;
  conexao := TConexao.Create('ManifestarDFePorChave');
  Acbr := nil;
  try
    CNPJConsulta := SomenteNumeros(ParametroStr(conexao, 'cnpj'));
    Acbr := CreateAcbrNf(conexao);
    Acbr.Configuracoes.Geral.ModeloDF := moNFe;
    Acbr.EventoNFe.Evento.Clear;
    Acbr.EventoNFe.idLote := 1;
    with Acbr.EventoNFe.Evento.New do
    begin
      infEvento.cOrgao := 91;
      infEvento.chNFe := ChaveLimpa;
      infEvento.CNPJ := CNPJConsulta;
      infEvento.dhEvento := Now;
      infEvento.tpEvento := Evento;
      if Evento = teManifDestOperNaoRealizada then
        infEvento.detEvento.xJust := Justificativa;
    end;
    Acbr.EnviarEvento(1);
    with Acbr.WebServices.EnvEvento.EventoRetorno.retEvento.Items[0]
      .RetInfEvento do
    begin
      cStatEvento := cStat;
      Result.AddPair('chave', ChaveLimpa);
      Result.AddPair('tipo', Tipo);
      Result.AddPair('evento', DescricaoEvento);
      Result.AddPair('cStat', TJSONNumber.Create(cStat));
      XMotivoEvento := XMotivo;
      Result.AddPair('xMotivo', XMotivo);
      Result.AddPair('nProt', nProt);
      Result.AddPair('dhRegEvento', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        dhRegEvento));
    end;
    if (cStatEvento = 135) or (cStatEvento = 136) or (cStatEvento = 573) then
    begin
      Result.AddPair('manifestada',
        TJSONBool.Create(RegistrarManifestacaoDFe(conexao, ChaveLimpa, Tipo,
        Origem, XMotivoEvento, cStatEvento)));
      PastaDFE := PastaDocsDFe;
      ForceDirectories(PastaDFE);
      XMLCompleto := BaixarXMLDFePorChave(Acbr, ParametroStr(conexao, 'estado'),
        CNPJConsulta, ChaveLimpa, PastaDFE);
      AtualizarXMLDFeBanco(conexao, ChaveLimpa, XMLCompleto);
      Result.AddPair('xml_baixado', TJSONBool.Create(XMLCompleto <> ''));
      if XMLCompleto <> '' then
      begin
        Result.AddPair('caminho_xml', PastaDFE + 'CHAVE_' + ChaveLimpa
          + '.xml');
        try
          Result.AddPair('importada',
            TJSONBool.Create(ImportarNotaFiscalDFeXML(conexao, XMLCompleto)));
        except
          on E: Exception do
          begin
            Result.AddPair('importada', TJSONBool.Create(False));
            Result.AddPair('erro_importacao', E.Message);
          end;
        end;
      end;
    end;
  except
    on E: Exception do
    begin
      Result.Free;
      Result := TJSONObject.Create;
      Result.AddPair('erro', E.Message);
    end;
  end;
  Acbr.Free;
  conexao.Free;
end;

function ManifestarDFePendentesAutomatico: Integer;
var
  conexao: TConexao;
  Qry: TFDQuery;
  Retorno: TJSONObject;
  valor: TJSONValue;
  Tipo, chave: String;
begin
  Result := 0;
  conexao := TConexao.Create('ManifestarDFePendentesAutomatico');
  Qry := nil;
  try
    if not DFeHabilitado(conexao) then
      Exit;

    Tipo := TipoManifestacaoDFePadrao(conexao);
    if Tipo = '' then
      Exit;

    Qry := conexao.CriaQRY;
    Qry.SQL.Add('SELECT dfe.chave FROM dfe_documento dfe ' +
      'LEFT JOIN nota_fiscal nf ON nf.chave COLLATE utf8mb4_general_ci = dfe.chave COLLATE utf8mb4_general_ci '
      + 'WHERE COALESCE(dfe.manifestada, 0) = 0 AND nf.id IS NULL ' +
      'ORDER BY dfe.data_emissao DESC LIMIT 50');
    Qry.Open;

    while not Qry.Eof do
    begin
      chave := Qry.FieldByName('chave').AsString;
      Retorno := ManifestarDFePorChave(chave, Tipo, '', 'automatico');
      try
        valor := Retorno.GetValue('manifestada');
        if Assigned(valor) and SameText(valor.Value, 'true') then
          Inc(Result);
      finally
        Retorno.Free;
      end;
      Qry.Next;
    end;
  finally
    Qry.Free;
    conexao.Free;
  end;
end;

procedure AtualizarXMLDFeBanco(conexao: TConexao; const chave, XML: String);
begin
  if Trim(XML) = '' then
    Exit;
  conexao.SQL.Add('UPDATE dfe_documento SET xml_base64 = :xml_base64, ' +
    'tipo = :tipo WHERE chave = :chave');
  conexao.Parametros('xml_base64', TNetEncoding.Base64.Encode(XML));
  if XMLDFeEhResumo(XML) then
    conexao.Parametros('tipo', 'resumo')
  else
    conexao.Parametros('tipo', 'nfe');
  conexao.Parametros('chave', chave);
  conexao.ExecuteSQL;
end;

function DecodificarTextoXML(const valor: String): String;
begin
  Result := valor;
  Result := StringReplace(Result, '&amp;', '&', [rfReplaceAll]);
  Result := StringReplace(Result, '&lt;', '<', [rfReplaceAll]);
  Result := StringReplace(Result, '&gt;', '>', [rfReplaceAll]);
  Result := StringReplace(Result, '&quot;', '"', [rfReplaceAll]);
  Result := StringReplace(Result, '&apos;', '''', [rfReplaceAll]);
end;

function TextoTagXML(const XML, Nome: String): String;
var
  Match: TMatch;
begin
  Result := '';
  Match := TRegEx.Match(XML, '<(?:[A-Za-z0-9_]+:)?' + Nome +
    '\b[^>]*>(.*?)</(?:[A-Za-z0-9_]+:)?' + Nome + '>',
    [roIgnoreCase, roSingleLine]);
  if Match.Success then
    Result := Trim(DecodificarTextoXML(Match.Groups[1].Value));
end;

function BlocoTagXML(const XML, Nome: String): String;
var
  Match: TMatch;
begin
  Result := '';
  Match := TRegEx.Match(XML, '<(?:[A-Za-z0-9_]+:)?' + Nome +
    '\b[^>]*>.*?</(?:[A-Za-z0-9_]+:)?' + Nome + '>',
    [roIgnoreCase, roSingleLine]);
  if Match.Success then
    Result := Match.Value;
end;

function AtributoTagXML(const XML, Nome, Atributo: String): String;
var
  Match: TMatch;
begin
  Result := '';
  Match := TRegEx.Match(XML, '<(?:[A-Za-z0-9_]+:)?' + Nome + '\b[^>]*\s' +
    Atributo + '\s*=\s*["'']([^"'']+)["'']', [roIgnoreCase, roSingleLine]);
  if Match.Success then
    Result := Trim(DecodificarTextoXML(Match.Groups[1].Value));
end;

function ValorTagXML(const XML, Nome: String): Double;
var
  fs: TFormatSettings;
begin
  fs := TFormatSettings.Create;
  fs.DecimalSeparator := '.';
  Result := StrToFloatDef(TextoTagXML(XML, Nome), 0, fs);
end;

function FormatarValorNotaFiscal(valor: Double): string;
var
  FmtMoeda: TFormatSettings;
begin
  FmtMoeda := TFormatSettings.Create;
  FmtMoeda.DecimalSeparator := ',';
  FmtMoeda.ThousandSeparator := '.';
  Result := FormatFloat('#,##0.00', valor, FmtMoeda);
end;

procedure RegistrarAlertaNotaFiscalBaixada(conexao: TConexao;
  const CodigoNota, FornecedorNome, chave: string; ValorNota: Double);
var
  Mensagem, ValorFormatado: string;
  FmtBanco: TFormatSettings;
begin
  ValorFormatado := FormatarValorNotaFiscal(ValorNota);
  Mensagem := 'Nova nota fiscal importada via XML ' + FornecedorNome + ' R$ ' +
    ValorFormatado;
  FmtBanco := TFormatSettings.Create;
  FmtBanco.DecimalSeparator := '.';
  conexao.SQL.Add('INSERT INTO alerta_sistema ' +
    '(tipo, origem, referencia_id, payload) ' +
    'VALUES (''DFE'', ''SISTEMA'', NULL, ' +
    'JSON_OBJECT(''mensagem'', :mensagem, ''fornecedor'', :fornecedor, ' +
    '''origem_entrada'', ''xml'', ''valor'', :valor, ''valor_numero'', :valor_numero, '
    + '''nota_id'', :nota_id, ''chave'', :chave))');
  conexao.Parametros('mensagem', Mensagem);
  conexao.Parametros('fornecedor', FornecedorNome);
  conexao.Parametros('valor', 'R$ ' + ValorFormatado);
  conexao.Parametros('valor_numero', FormatFloat('0.00', ValorNota, FmtBanco));
  conexao.Parametros('nota_id', CodigoNota);
  conexao.Parametros('chave', chave);
  conexao.ExecuteSQL;
end;

function DataXML(const valor: String): TDateTime;
begin
  Result := Now;
  if Trim(valor) = '' then
    Exit;
  try
    Result := ISO8601ToDate(valor, False);
  except
    Result := StrToDateTimeDef(Copy(valor, 1, 10), Now);
  end;
end;

function ImportarNotaFiscalDFeXML(conexao: TConexao; const XML: String)
  : Boolean;
var
  InfNFeXML, IdeXML, EmitXML, TotalXML, ICMSTotXML, DetXML, ProdXML: String;
  CodigoFornecedor, CodigoNota, CodigoFornecedorItem: String;
  chave, CNPJFornecedor, NomeFornecedor, DataEmissaoTexto: String;
  Fmt: TFormatSettings;
  Matches: TMatchCollection;
  I: Integer;
  ValorNota: Double;
begin
  Result := False;
  if (Trim(XML) = '') or XMLDFeEhResumo(XML) then
    Exit;
  InfNFeXML := BlocoTagXML(XML, 'infNFe');
  if InfNFeXML = '' then
    Exit;
  IdeXML := BlocoTagXML(InfNFeXML, 'ide');
  EmitXML := BlocoTagXML(InfNFeXML, 'emit');
  TotalXML := BlocoTagXML(InfNFeXML, 'total');
  ICMSTotXML := BlocoTagXML(TotalXML, 'ICMSTot');
  chave := SomenteNumeros(AtributoTagXML(InfNFeXML, 'infNFe', 'Id'));
  if chave = '' then
    chave := TextoTagXML(XML, 'chNFe');
  if Length(chave) <> 44 then
    Exit;
  conexao.SQL.Add('select id, 0 as zero from nota_fiscal where chave = :chave');
  conexao.Parametros('chave', chave);
  CodigoNota := conexao.FieldByName('id');
  if (CodigoNota <> '') and (CodigoNota <> '0') then
  begin
    Result := True;
    Exit;
  end;
  CNPJFornecedor := TextoTagXML(EmitXML, 'CNPJ');
  if CNPJFornecedor = '' then
    CNPJFornecedor := TextoTagXML(EmitXML, 'CPF');
  NomeFornecedor := TextoTagXML(EmitXML, 'xNome');
  conexao.SQL.Add('select id, 0 as zero from fornecedor where cnpj = :cnpj');
  conexao.Parametros('cnpj', CNPJFornecedor);
  CodigoFornecedor := conexao.FieldByName('id');
  if (CodigoFornecedor = '') or (CodigoFornecedor = '0') then
  begin
    conexao.SQL.Add
      ('insert into fornecedor (id, cnpj, nome, criado_em) values (UUID(), :cnpj, :nome, NOW())');
    conexao.Parametros('cnpj', CNPJFornecedor);
    conexao.Parametros('nome', NomeFornecedor);
    conexao.ExecuteSQL;
    conexao.SQL.Add('select id, 0 as zero from fornecedor where cnpj = :cnpj');
    conexao.Parametros('cnpj', CNPJFornecedor);
    CodigoFornecedor := conexao.FieldByName('id');
  end;
  DataEmissaoTexto := TextoTagXML(IdeXML, 'dhEmi');
  if DataEmissaoTexto = '' then
    DataEmissaoTexto := TextoTagXML(IdeXML, 'dEmi');
  ValorNota := ValorTagXML(ICMSTotXML, 'vNF');
  conexao.SQL.Add('select UUID() as id, 0 as zero');
  CodigoNota := conexao.FieldByName('id');
  if (CodigoNota = '') or (CodigoNota = '0') then
    raise Exception.Create('Nao foi possivel gerar o ID da nota fiscal.');
  conexao.SQL.Add
    ('insert into nota_fiscal (id, fornecedor_id, serie, numero, chave, modelo, tipo, data_emissao, data_entrada, vNF, vFrete, vDesc, vOutro, xml_original, status_importacao, criado_em)');
  conexao.SQL.Add
    ('values (:id, :fornecedor_id, :serie, :numero, :chave, :modelo, :tipo, :data_emissao, NOW(), :vNF, :vFrete, :vDesc, :vOutro, :xml_original, :status_importacao, NOW())');
  conexao.Parametros('id', CodigoNota);
  conexao.Parametros('fornecedor_id', CodigoFornecedor);
  conexao.Parametros('serie', TextoTagXML(IdeXML, 'serie'));
  conexao.Parametros('numero', TextoTagXML(IdeXML, 'nNF'));
  conexao.Parametros('chave', chave);
  conexao.Parametros('modelo', TextoTagXML(IdeXML, 'mod'));
  conexao.Parametros('tipo', 'NF');
  conexao.Parametros('data_emissao', FormatDateTime('yyyy-mm-dd hh:nn:ss',
    DataXML(DataEmissaoTexto)));
  conexao.Parametros('vNF', ValorNota);
  conexao.Parametros('vFrete', ValorTagXML(ICMSTotXML, 'vFrete'));
  conexao.Parametros('vDesc', ValorTagXML(ICMSTotXML, 'vDesc'));
  conexao.Parametros('vOutro', ValorTagXML(ICMSTotXML, 'vOutro'));
  conexao.Parametros('xml_original', XML);
  conexao.Parametros('status_importacao', 'pendente');
  conexao.ExecuteSQL;
  Fmt := TFormatSettings.Create;
  Fmt.DecimalSeparator := '.';
  Matches := TRegEx.Matches(InfNFeXML,
    '<(?:[A-Za-z0-9_]+:)?det\b[^>]*>.*?</(?:[A-Za-z0-9_]+:)?det>',
    [roIgnoreCase, roSingleLine]);
  for I := 0 to Matches.Count - 1 do
  begin
    DetXML := Matches.Item[I].Value;
    ProdXML := BlocoTagXML(DetXML, 'prod');
    if ProdXML = '' then
      Continue;
    conexao.SQL.Add
      ('select id, 0 as zero from fornecedor_item where fornecedor_id = :fornecedor and cprod = :cprod');
    conexao.Parametros('fornecedor', CodigoFornecedor);
    conexao.Parametros('cprod', TextoTagXML(ProdXML, 'cProd'));
    CodigoFornecedorItem := conexao.FieldByName('id');
    if (CodigoFornecedorItem = '') or (CodigoFornecedorItem = '0') then
    begin
      conexao.SQL.Add
        ('insert into fornecedor_item (id, fornecedor_id, cprod, xProd, NCM, CFOP, uCom, criado_em)');
      conexao.SQL.Add
        ('values (UUID(), :fornecedor_id, :cprod, :xProd, :NCM, :CFOP, :uCom, NOW())');
      conexao.Parametros('fornecedor_id', CodigoFornecedor);
      conexao.Parametros('cprod', TextoTagXML(ProdXML, 'cProd'));
      conexao.Parametros('xProd', TextoTagXML(ProdXML, 'xProd'));
      conexao.Parametros('NCM', TextoTagXML(ProdXML, 'NCM'));
      conexao.Parametros('CFOP', TextoTagXML(ProdXML, 'CFOP'));
      conexao.Parametros('uCom', TextoTagXML(ProdXML, 'uCom'));
      conexao.ExecuteSQL;
      conexao.SQL.Add
        ('select id, 0 as zero from fornecedor_item where fornecedor_id = :fornecedor and cprod = :cprod');
      conexao.Parametros('fornecedor', CodigoFornecedor);
      conexao.Parametros('cprod', TextoTagXML(ProdXML, 'cProd'));
      CodigoFornecedorItem := conexao.FieldByName('id');
    end;
    conexao.SQL.Add
      ('insert into nota_fiscal_item (id, nota_fiscal_id, fornecedor_item_id, cProd, xProd, NCM, CFOP, qCom, uCom, vUnCom, vProd, vDesc, vFrete, vOutro, uTrib, criado_em)');
    conexao.SQL.Add
      ('values (UUID(), :nota_fiscal_id, :fornecedor_item_id, :cProd, :xProd, :NCM, :CFOP, :qCom, :uCom, :vUnCom, :vProd, :vDesc, :vFrete, :vOutro, :uTrib, NOW())');
    conexao.Parametros('nota_fiscal_id', CodigoNota);
    conexao.Parametros('fornecedor_item_id', CodigoFornecedorItem);
    conexao.Parametros('cProd', TextoTagXML(ProdXML, 'cProd'));
    conexao.Parametros('xProd', TextoTagXML(ProdXML, 'xProd'));
    conexao.Parametros('NCM', TextoTagXML(ProdXML, 'NCM'));
    conexao.Parametros('CFOP', TextoTagXML(ProdXML, 'CFOP'));
    conexao.Parametros('qCom', FormatFloat('0.######', ValorTagXML(ProdXML,
      'qCom'), Fmt));
    conexao.Parametros('uCom', TextoTagXML(ProdXML, 'uCom'));
    conexao.Parametros('vUnCom', FormatFloat('0.######', ValorTagXML(ProdXML,
      'vUnCom'), Fmt));
    conexao.Parametros('vProd', FormatFloat('0.##', ValorTagXML(ProdXML,
      'vProd'), Fmt));
    conexao.Parametros('vDesc', FormatFloat('0.##', ValorTagXML(ProdXML,
      'vDesc'), Fmt));
    conexao.Parametros('vFrete', FormatFloat('0.##', ValorTagXML(ProdXML,
      'vFrete'), Fmt));
    conexao.Parametros('vOutro', FormatFloat('0.##', ValorTagXML(ProdXML,
      'vOutro'), Fmt));
    conexao.Parametros('uTrib', TextoTagXML(ProdXML, 'uTrib'));
    conexao.ExecuteSQL;
  end;
  RegistrarAlertaNotaFiscalBaixada(conexao, CodigoNota, NomeFornecedor, chave,
    ValorNota);
  Result := True;
end;

function ConsultarXMLDFePorChave(const chave: String): TJSONObject;
var
  conexao: TConexao;
  Acbr: TACBrNFe;
  ChaveLimpa, CNPJConsulta, PastaDFE, caminho, XML, motivoStatus: String;
  Importada: Boolean;
begin
  Result := TJSONObject.Create;
  ChaveLimpa := SomenteNumeros(chave);
  if Length(ChaveLimpa) <> 44 then
  begin
    Result.AddPair('erro', 'Chave DFe invalida.');
    Exit;
  end;
  conexao := TConexao.Create('ConsultarXMLDFePorChave');
  Acbr := nil;
  try
    XML := XMLDFeLocalPorChave(ChaveLimpa, caminho);
    if XML = '' then
      XML := XMLDFeBancoPorChave(conexao, ChaveLimpa);
    if XML = '' then
    begin
      if not StatusServicoNFeDisponivel(motivoStatus) then
      begin
        Result.AddPair('chave', ChaveLimpa);
        Result.AddPair('baixado', TJSONBool.Create(False));
        Result.AddPair('motivo', motivoStatus);
        Exit;
      end;
      CNPJConsulta := SomenteNumeros(ParametroStr(conexao, 'cnpj'));
      PastaDFE := PastaDocsDFe;
      ForceDirectories(PastaDFE);
      Acbr := CreateAcbrNf(conexao);
      Acbr.Configuracoes.Geral.ModeloDF := moNFe;
      ManifestarDFeCiencia(Acbr, CNPJConsulta, ChaveLimpa);
      XML := BaixarXMLDFePorChave(Acbr, ParametroStr(conexao, 'estado'),
        CNPJConsulta, ChaveLimpa, PastaDFE);
      caminho := PastaDFE + 'CHAVE_' + ChaveLimpa + '.xml';
      AtualizarXMLDFeBanco(conexao, ChaveLimpa, XML);
    end;
    Result.AddPair('chave', ChaveLimpa);
    Result.AddPair('baixado', TJSONBool.Create(XML <> ''));
    Result.AddPair('caminho', caminho);
    if XMLDFeEhResumo(XML) then
      Result.AddPair('tipo', 'resumo')
    else
      Result.AddPair('tipo', 'nfe');
    Result.AddPair('xml_base64', TNetEncoding.Base64.Encode(XML));
    Result.AddPair('xml', XML);
    if XMLDFeEhResumo(XML) then
      Result.AddPair('motivo',
        'SEFAZ retornou apenas resumo. Manifestacao feita; tente novamente em alguns minutos.')
    else
    begin
      try
        Importada := ImportarNotaFiscalDFeXML(conexao, XML);
        Result.AddPair('importada', TJSONBool.Create(Importada));
      except
        on E: Exception do
        begin
          Result.AddPair('importada', TJSONBool.Create(False));
          Result.AddPair('erro_importacao', E.Message);
        end;
      end;
    end
  finally
    Acbr.Free;
    conexao.Free;
  end;
end;

function SimularImportacaoDFeArquivo(const caminho: String): TJSONObject;
var
  conexao: TConexao;
  XML, chave, InfNFeXML: String;
  Importada: Boolean;
begin
  Result := TJSONObject.Create;
  Result.AddPair('caminho', caminho);
  if Trim(caminho) = '' then
  begin
    Result.AddPair('erro', 'Caminho do XML nao informado.');
    Exit;
  end;
  if not TFile.Exists(caminho) then
  begin
    Result.AddPair('erro', 'Arquivo XML nao encontrado: ' + caminho);
    Exit;
  end;
  XML := TFile.ReadAllText(caminho, TEncoding.UTF8);
  if Trim(XML) = '' then
  begin
    Result.AddPair('erro', 'Arquivo XML vazio.');
    Exit;
  end;
  if XMLDFeEhResumo(XML) then
  begin
    Result.AddPair('baixado', TJSONBool.Create(True));
    Result.AddPair('tipo', 'resumo');
    Result.AddPair('importada', TJSONBool.Create(False));
    Result.AddPair('motivo',
      'XML informado e resumo de DFe. Informe o XML completo da NFe.');
    Exit;
  end;
  InfNFeXML := BlocoTagXML(XML, 'infNFe');
  chave := SomenteNumeros(AtributoTagXML(InfNFeXML, 'infNFe', 'Id'));
  if chave = '' then
    chave := TextoTagXML(XML, 'chNFe');
  if Length(chave) <> 44 then
  begin
    Result.AddPair('erro', 'XML invalido: chave da NFe nao encontrada.');
    Exit;
  end;
  Result.AddPair('chave', chave);
  Result.AddPair('baixado', TJSONBool.Create(True));
  Result.AddPair('tipo', 'nfe');
  conexao := TConexao.Create('SimularImportacaoDFeArquivo');
  try
    try
      Importada := ImportarNotaFiscalDFeXML(conexao, XML);
      AtualizarXMLDFeBanco(conexao, chave, XML);
      Result.AddPair('importada', TJSONBool.Create(Importada));
    except
      on E: Exception do
      begin
        Result.AddPair('importada', TJSONBool.Create(False));
        Result.AddPair('erro_importacao', E.Message);
      end;
    end;
  finally
    conexao.Free;
  end;
end;

procedure GravarConsultaDFe(conexao: TConexao;
  const CNPJ, UltimoNSU, ambiente: String; QtdDocumentos: Integer;
  Documentos: TJsonArray);
var
  idConsulta, idDoc, I: Integer;
  JSONDoc: TJSONObject;
  valor: TJSONValue;
begin
  idConsulta := conexao.GerarID('dfe_consulta', 'id');
  conexao.SQL.Add
    ('INSERT INTO dfe_consulta (id, cnpj_empresa, data_consulta, hora_consulta, ultimo_nsu, qtd_documentos, ambiente) '
    + 'VALUES (:id, :cnpj_empresa, curdate(), curtime(), :ultimo_nsu, :qtd_documentos, :ambiente)');
  conexao.Parametros('id', idConsulta);
  conexao.Parametros('cnpj_empresa', CNPJ);
  conexao.Parametros('ultimo_nsu', UltimoNSU);
  conexao.Parametros('qtd_documentos', QtdDocumentos);
  conexao.Parametros('ambiente', ambiente);
  conexao.ExecuteSQL;
  if not Assigned(Documentos) then
    Exit;
  for I := 0 to Documentos.Count - 1 do
  begin
    JSONDoc := Documentos.Items[I] as TJSONObject;
    idDoc := conexao.GerarID('dfe_documento', 'id');
    conexao.SQL.Add
      ('INSERT INTO dfe_documento (id, id_consulta, nsu, chave, cnpj_emitente, nome_emitente, valor, data_emissao, situacao, xml_base64, tipo) '
      + 'VALUES (:id, :id_consulta, :nsu, :chave, :cnpj_emitente, :nome_emitente, :valor, :data_emissao, :situacao, :xml_base64, :tipo) '
      + 'ON DUPLICATE KEY UPDATE id_consulta = VALUES(id_consulta), nsu = VALUES(nsu), cnpj_emitente = VALUES(cnpj_emitente), '
      + 'nome_emitente = VALUES(nome_emitente), valor = VALUES(valor), data_emissao = VALUES(data_emissao), situacao = VALUES(situacao), '
      + 'xml_base64 = VALUES(xml_base64), tipo = VALUES(tipo)');
    conexao.Parametros('id', idDoc);
    conexao.Parametros('id_consulta', idConsulta);
    conexao.Parametros('nsu', JSONDoc.GetValue('nsu').Value);
    conexao.Parametros('chave', JSONDoc.GetValue('chave').Value);
    conexao.Parametros('cnpj_emitente',
      JSONDoc.GetValue('cnpj_emitente').Value);
    conexao.Parametros('nome_emitente', JSONDoc.GetValue('emitente').Value);
    conexao.Parametros('valor', JSONDoc.GetValue('valor').Value);
    conexao.Parametros('data_emissao', JSONDoc.GetValue('data_emissao').Value);
    conexao.Parametros('situacao', JSONDoc.GetValue('situacao').Value);
    valor := JSONDoc.GetValue('xml_base64');
    if Assigned(valor) then
      conexao.Parametros('xml_base64', valor.Value)
    else
      conexao.Parametros('xml_base64', '');
    valor := JSONDoc.GetValue('tipo');
    if Assigned(valor) then
      conexao.Parametros('tipo', valor.Value)
    else
      conexao.Parametros('tipo', 'resumo');
    conexao.ExecuteSQL;
  end;
end;

function ConsultarDFeSefaz(const CNPJ: String): TJSONObject;
var
  conexao: TConexao;
  Acbr: TACBrNFe;
  AcbrDownload: TACBrNFe;
  CNPJConsulta, UltimoNSU, ambiente, PastaDFE, NomeArquivo, XMLText,
    XMLCompleto: String;
  MensagemDFe, motivoStatus: String;
  Documentos: TJsonArray;
  JSONInfo, JSONItem: TJSONObject;
  SL: TStringList;
  I: Integer;
begin
  conexao := TConexao.Create('ConsultarDFeSefaz');
  Acbr := nil;
  AcbrDownload := nil;
  Result := TJSONObject.Create;
  Documentos := TJsonArray.Create;
  try
    CNPJConsulta := SomenteNumeros(CNPJ);
    if CNPJConsulta = '' then
      CNPJConsulta := SomenteNumeros(ParametroStr(conexao, 'cnpj'));
    if CNPJConsulta = '' then
      raise Exception.Create('CNPJ nao configurado para consulta DFe.');
    Acbr := CreateAcbrNf(conexao);
    Acbr.Configuracoes.Geral.ModeloDF := moNFe;
    ambiente := AmbienteDFeTexto(Acbr.Configuracoes.WebServices.ambiente);
    UltimoNSU := UltimoNSUDFe(conexao, CNPJConsulta, ambiente);
    if not ConsultaDFeLiberada(conexao, CNPJConsulta, ambiente, MensagemDFe)
    then
    begin
      JSONInfo := TJSONObject.Create;
      JSONInfo.AddPair('cnpj', CNPJConsulta);
      JSONInfo.AddPair('ambiente', ambiente);
      JSONInfo.AddPair('ultimo_nsu', UltimoNSU);
      JSONInfo.AddPair('qtd_documentos', TJSONNumber.Create(0));
      JSONInfo.AddPair('status', TJSONNumber.Create(0));
      JSONInfo.AddPair('motivo', MensagemDFe);
      Result.AddPair('consulta', JSONInfo);
      Result.AddPair('documentos', Documentos);
      Documentos := nil;
    end
    else if not StatusServicoNFeDisponivel(motivoStatus) then
    begin
      JSONInfo := TJSONObject.Create;
      JSONInfo.AddPair('cnpj', CNPJConsulta);
      JSONInfo.AddPair('ambiente', ambiente);
      JSONInfo.AddPair('ultimo_nsu', UltimoNSU);
      JSONInfo.AddPair('qtd_documentos', TJSONNumber.Create(0));
      JSONInfo.AddPair('status', TJSONNumber.Create(0));
      JSONInfo.AddPair('motivo', motivoStatus);
      Result.AddPair('consulta', JSONInfo);
      Result.AddPair('documentos', Documentos);
      Documentos := nil;
    end
    else if not ReservarConsultaDFe(MensagemDFe) then
    begin
      JSONInfo := TJSONObject.Create;
      JSONInfo.AddPair('cnpj', CNPJConsulta);
      JSONInfo.AddPair('ambiente', ambiente);
      JSONInfo.AddPair('ultimo_nsu', UltimoNSU);
      JSONInfo.AddPair('qtd_documentos', TJSONNumber.Create(0));
      JSONInfo.AddPair('status', TJSONNumber.Create(0));
      JSONInfo.AddPair('motivo', MensagemDFe);
      Result.AddPair('consulta', JSONInfo);
      Result.AddPair('documentos', Documentos);
      Documentos := nil;
    end
    else
    begin
      PastaDFE := PastaDocsDFe;
      ForceDirectories(PastaDFE);
      GravarControleDFeParametro(conexao, UltimoNSU);
      Acbr.DistribuicaoDFePorUltNSU
        (UFtoCUF(UpperCase(ParametroStr(conexao, 'estado'))), CNPJConsulta,
        UltimoNSU);
      with Acbr.WebServices.DistribuicaoDFe.retDistDFeInt do
      begin
        if cStat = 138 then
        begin
          UltimoNSU := ultNSU;
          for I := 0 to docZip.Count - 1 do
          begin
            XMLText := Trim(docZip[I].XML);
            if XMLText = '' then
              Continue;
            NomeArquivo := PastaDFE + 'NSU_' + docZip[I].NSU + '.xml';
            SL := TStringList.Create;
            try
              SL.Text := docZip[I].XML;
              SL.SaveToFile(NomeArquivo);
            finally
              SL.Free;
            end;
            if docZip[I].resDFe.chDFe <> '' then
            begin
              if XMLDFeEhResumo(XMLText) and (docZip[I].resDFe.chDFe <> '') then
              begin
                try
                  if not Assigned(AcbrDownload) then
                  begin
                    AcbrDownload := CreateAcbrNf(conexao);
                    AcbrDownload.Configuracoes.Geral.ModeloDF := moNFe;
                  end;
                  if ManifestarDFeCiencia(AcbrDownload, CNPJConsulta,
                    docZip[I].resDFe.chDFe) then
                  begin
                    XMLCompleto := BaixarXMLDFePorChave(AcbrDownload,
                      ParametroStr(conexao, 'estado'), CNPJConsulta,
                      docZip[I].resDFe.chDFe, PastaDFE);
                    if XMLCompleto <> '' then
                      XMLText := XMLCompleto;
                  end;
                except
                end;
              end;
              JSONItem := TJSONObject.Create;
              JSONItem.AddPair('nsu', docZip[I].NSU);
              JSONItem.AddPair('chave', docZip[I].resDFe.chDFe);
              JSONItem.AddPair('cnpj_emitente', docZip[I].resDFe.CNPJCPF);
              JSONItem.AddPair('emitente', docZip[I].resDFe.xNome);
              JSONItem.AddPair('valor',
                TJSONNumber.Create(docZip[I].resDFe.vNF));
              JSONItem.AddPair('data_emissao',
                FormatDateTime('yyyy-mm-dd hh:nn:ss', docZip[I].resDFe.dhEmi));
              JSONItem.AddPair('situacao', GetEnumName(TypeInfo(TSituacaoDFe),
                Ord(docZip[I].resDFe.cSitDFe)));
              JSONItem.AddPair('xml_base64',
                TNetEncoding.Base64.Encode(XMLText));
              if XMLDFeEhResumo(XMLText) then
                JSONItem.AddPair('tipo', 'resumo')
              else
                JSONItem.AddPair('tipo', 'nfe');
              Documentos.AddElement(JSONItem);
            end;
          end;
        end;
        if (cStat = 137) and
          (StrToInt64Def(maxNSU, 0) > StrToInt64Def(ultNSU, 0)) then
          UltimoNSU := maxNSU;
        GravarConsultaDFe(conexao, CNPJConsulta, UltimoNSU, ambiente,
          docZip.Count, Documentos);
        GravarControleDFeParametro(conexao, UltimoNSU);
        JSONInfo := TJSONObject.Create;
        JSONInfo.AddPair('cnpj', CNPJConsulta);
        JSONInfo.AddPair('ambiente', ambiente);
        JSONInfo.AddPair('ultimo_nsu', UltimoNSU);
        JSONInfo.AddPair('max_nsu', maxNSU);
        JSONInfo.AddPair('qtd_documentos', TJSONNumber.Create(docZip.Count));
        JSONInfo.AddPair('cstat', TJSONNumber.Create(cStat));
        JSONInfo.AddPair('motivo', XMotivo);
        Result.AddPair('consulta', JSONInfo);
        Result.AddPair('documentos', Documentos);
        Documentos := nil;
      end;
    end;
  except
    on E: Exception do
    begin
      Documentos.Free;
      Result.Free;
      Result := TJSONObject.Create;
      Result.AddPair('erro', E.Message);
    end;
  end;
  Acbr.Free;
  AcbrDownload.Free;
  conexao.Free;
end;

procedure SalvarParametroConfiguracao(const chave, valor: String);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('SalvarParametroConfiguracao');
  try
    conexao.SalvarParametro(chave, valor);
  finally
    conexao.Free;
  end;
end;

function LerParametroConfiguracao(const chave: String): String;
var
  conexao: TConexao;
  Qry: TFDQuery;
begin
  Result := '';
  conexao := TConexao.Create('LerParametroConfiguracao');
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text := 'SELECT valor FROM configuracoes WHERE chave = :chave';
    Qry.ParamByName('chave').AsWideString := chave;
    Qry.Open;
    if not Qry.Eof then
      Result := Qry.FieldByName('valor').AsString;
  finally
    Qry.Free;
    conexao.Free;
  end;
end;

function MontarJSONStatusServicoNFeGravado: TJSONObject;
var
  JSONSalvo, cStat, motivo, erro: String;
  valor: TJSONValue;
  Memoria: TJSONObject;
begin
  Result := TJSONObject.Create;
  JSONSalvo := LerParametroConfiguracao('nfe_status_servico');
  cStat := LerParametroConfiguracao('nfe_status_servico_cstat');
  motivo := LerParametroConfiguracao('nfe_status_servico_motivo');
  erro := LerParametroConfiguracao('nfe_status_servico_erro');
  Result.AddPair('gravado', TJSONBool.Create(JSONSalvo <> ''));
  Result.AddPair('cStat', cStat);
  Result.AddPair('xMotivo', motivo);
  Result.AddPair('erro', erro);
  if JSONSalvo <> '' then
  begin
    valor := TJSONObject.ParseJSONValue(JSONSalvo);
    if Assigned(valor) then
      Result.AddPair('dados', valor)
    else
      Result.AddPair('dados_raw', JSONSalvo);
  end;
  CriticalStatusServicoNFe.Enter;
  try
    Memoria := TJSONObject.Create;
    Memoria.AddPair('cStat', TJSONNumber.Create(UltimoStatusServicoNFeCStat));
    Memoria.AddPair('xMotivo', UltimoStatusServicoNFeMotivo);
    if UltimoStatusServicoNFeDataHora > 0 then
      Memoria.AddPair('consultado_em', FormatDateTime('yyyy-mm-dd hh:nn:ss',
        UltimoStatusServicoNFeDataHora))
    else
      Memoria.AddPair('consultado_em', '');
    Memoria.AddPair('json', UltimoStatusServicoNFeJSON);
    Result.AddPair('cache_memoria', Memoria);
  finally
    CriticalStatusServicoNFe.Leave;
  end;
end;

procedure AtualizarCacheStatusServicoNFe(const StatusJSON: String;
  cStat: Integer; const motivo: String);
begin
  CriticalStatusServicoNFe.Enter;
  try
    UltimoStatusServicoNFeJSON := StatusJSON;
    UltimoStatusServicoNFeCStat := cStat;
    UltimoStatusServicoNFeMotivo := motivo;
    UltimoStatusServicoNFeDataHora := Now;
  finally
    CriticalStatusServicoNFe.Leave;
  end;
end;

function StatusServicoNFeDisponivel(var motivo: String): Boolean;
begin
  Result := True;
  motivo := '';
  CriticalStatusServicoNFe.Enter;
  try
    if UltimoStatusServicoNFeDataHora = 0 then
      Exit;
    Result := UltimoStatusServicoNFeCStat = 107;
    if not Result then
      motivo := 'Servico NFe indisponivel no cache local: ' +
        UltimoStatusServicoNFeCStat.ToString + ' - ' +
        UltimoStatusServicoNFeMotivo;
  finally
    CriticalStatusServicoNFe.Leave;
  end;
end;

function ConsultarStatusServicoNFe: TJSONObject;
var
  conexao: TConexao;
  Acbr: TACBrNFe;
  Status: TJSONObject;
begin
  conexao := TConexao.Create('ConsultarStatusServicoNFe');
  Acbr := nil;
  Result := TJSONObject.Create;
  try
    Acbr := CreateAcbrNf(conexao);
    Acbr.Configuracoes.Geral.ModeloDF := moNFe;
    Acbr.WebServices.StatusServico.Executar;
    Status := TJSONObject.Create;
    Status.AddPair('tpAmb',
      AmbienteDFeTexto(Acbr.WebServices.StatusServico.tpAmb));
    Status.AddPair('verAplic', Acbr.WebServices.StatusServico.VerAplic);
    Status.AddPair('cStat',
      TJSONNumber.Create(Acbr.WebServices.StatusServico.cStat));
    Status.AddPair('xMotivo', Acbr.WebServices.StatusServico.XMotivo);
    Status.AddPair('cUF',
      TJSONNumber.Create(Acbr.WebServices.StatusServico.cUF));
    Status.AddPair('dhRecbto', FormatDateTime('yyyy-mm-dd hh:nn:ss',
      Acbr.WebServices.StatusServico.dhRecbto));
    Status.AddPair('tMed',
      TJSONNumber.Create(Acbr.WebServices.StatusServico.TMed));
    Status.AddPair('dhRetorno', FormatDateTime('yyyy-mm-dd hh:nn:ss',
      Acbr.WebServices.StatusServico.dhRetorno));
    Status.AddPair('xObs', Acbr.WebServices.StatusServico.xObs);
    Status.AddPair('retWS', Acbr.WebServices.StatusServico.RetWS);
    Status.AddPair('retornoWS', Acbr.WebServices.StatusServico.RetornoWS);
    Status.AddPair('consultado_em', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
    Result.AddPair('status_servico', Status);
    AtualizarCacheStatusServicoNFe(Result.ToJSON,
      Acbr.WebServices.StatusServico.cStat,
      Acbr.WebServices.StatusServico.XMotivo);
    SalvarParametroConfiguracao('nfe_status_servico', Result.ToJSON);
    SalvarParametroConfiguracao('nfe_status_servico_cstat',
      Acbr.WebServices.StatusServico.cStat.ToString);
    SalvarParametroConfiguracao('nfe_status_servico_motivo',
      Acbr.WebServices.StatusServico.XMotivo);

  except
    on E: Exception do
    begin
      Result.Free;
      Result := TJSONObject.Create;
      Result.AddPair('erro', E.Message);
      AtualizarCacheStatusServicoNFe(Result.ToJSON, 0, E.Message);
      SalvarParametroConfiguracao('nfe_status_servico_erro', E.Message);
    end;
  end;
  Acbr.Free;
  conexao.Free;
end;

function GetNotasPendentesContabilidade: TJsonArray;
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');
  try
    conexao.SQL.Add('select * from pedido where nfce_chave <> ' +
      QuotedStr('CANCELADA') +
      ' and nfce_sinc_contabilidade = 0 and nfce_ambiente = 1 and data_pedido > '
      + QuotedStr('2024-08-01'));
    Result := conexao.ConsultaSQL;
  finally
    conexao.Free;
  end;
end;

procedure MarcarNotaSincronizadaContabilidade(const chave, caminho,
  path: String);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');
  try
    conexao.SQL.Add
      ('update pedido set nfce_sinc_contabilidade = 1 where nfce_chave = :nfce_chave');
    conexao.Parametros('nfce_chave', chave);
    conexao.ExecuteSQL;
    conexao.SQL.Add('delete from pedido_nfce where chave = :chave');
    conexao.Parametros('chave', chave);
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into pedido_nfce (id,id_pedido,chave,protocolo,caminho,path) ' +
      'select :id,codigo,nfce_chave,nfce_protocolo,:caminho,:path ' +
      'from pedido where nfce_chave = :chave');
    conexao.Parametros('id', conexao.GerarID('pedido_nfce', 'id'));
    conexao.Parametros('chave', chave);
    conexao.Parametros('caminho', caminho);
    conexao.Parametros('path', path);
    conexao.ExecuteSQL;
  finally
    conexao.Free;
  end;
end;

function GetImpressora(codigo: Integer; conexao: TConexao): TNFCeImpressora;
var
  Qry: TFDQuery;
begin
  Result.Driver := '';
  Result.TipoImpressao := 1;
  Qry := conexao.CriaQRY;
  Qry.SQL.Add('SELECT IFNULL(i.driver, ii.driver) as driver,');
  Qry.SQL.Add('IFNULL(i.tipo_impressao, ii.tipo_impressao) as tipo_impressao');
  Qry.SQL.Add('FROM pedido as p');
  Qry.SQL.Add('join caixa as c on  c.id = p.id_caixa');
  Qry.SQL.Add('left join usuario as u on u.codigo = c.id_usuario');
  Qry.SQL.Add('left join impressoras i on i.codigo = u.impressora');
  Qry.SQL.Add
    ('left join impressoras ii on ii.ativo = 1 and ii.impressora_padrao = 1');
  Qry.SQL.Add('where p.codigo = :codigo');
  Qry.ParamByName('codigo').AsInteger := codigo;
  try
    Qry.Open;
    if Qry.Active then
    begin
      Result.Driver := Qry.FieldByName('driver').AsString;
      Result.TipoImpressao := Qry.FieldByName('tipo_impressao').AsInteger;
    end;
  except

  end;
  Qry.Free;

end;

procedure EmailFiscal(chave, email: String);
var
  conexao: TConexao;
  Qry: TFDQuery;
  Enviar: Boolean;
  JSON: TJSONObject;
  user: String;
  req: iRequisicao;
begin

  conexao := TConexao.Create('EmailFiscal');
  Qry := conexao.CriaQRY;
  Qry.SQL.Add
    ('select pn.caminho as link, c.celular, c.email_nfce as email, c.codigo as codigo, nfce_protocolo as protocolo, nfce_data as data, nfce_hora as hora, valor_total_pedido as valor_total');
  Qry.SQL.Add('from pedido_nfce as pn');
  Qry.SQL.Add('join pedido as p on p.codigo = pn.id_pedido');
  Qry.SQL.Add('join cliente as c on c.codigo = p.codigo_cliente');

  Qry.SQL.Add('where pn.chave = :chave');
  Qry.ParamByName('chave').AsString := chave;
  Qry.Open;
  if Qry.Active then
  begin
    if email = '' then
    begin
      email := Qry.FieldByName('email').AsString;
      Enviar := True;
    end;
    conexao.SQL.Add
      ('update cliente set email_nfce = :email where codigo = :codigo');
    conexao.Parametros('email', email);
    conexao.Parametros('codigo', Qry.FieldByName('codigo').AsInteger);
    conexao.ExecuteSQL;
    JSON := TJSONObject.Create;
    user := conexao.GetParametro('user_id');
    if user = '' then
      user := 'GOOPEDIR';

    JSON.AddPair('user_id', user);
    if Desenvolvimento then
      JSON.AddPair('celular', '5548998111156')
    else
      JSON.AddPair('celular', Qry.FieldByName('celular').AsString);

    JSON.AddPair('chave', chave);
    JSON.AddPair('protocolo', Qry.FieldByName('protocolo').AsString);
    JSON.AddPair('link', Qry.FieldByName('link').AsString);
    JSON.AddPair('valor_total', Qry.FieldByName('valor_total').AsFloat);

    if conexao.GetParametro('enviar_nfce_whatsapp') = '1' then
    begin
      req := iRequisicao.Create(nil);
      req.BaseURL := API_BASE_URL;
      req.URL := 'api/whatsapp/nota/enviar';
      req.Metodo := mPost;
      req.Body(JSON);
      try
        req.Execute
      except

      end;
      req.Free;
    end;

  end;
  Qry.Free;
  conexao.Free;

  if (Enviar) and (email <> '') then
  begin
    EnviarEmailNFCe(chave, email);
  end;

end;

initialization

CriticalConsultaDFe := TCriticalSection.Create;
CriticalStatusServicoNFe := TCriticalSection.Create;

finalization

if Assigned(ThreadStatusServicoNFe) then
begin
  ThreadStatusServicoNFe.Terminate;
  ThreadStatusServicoNFe.WaitFor;
  FreeAndNil(ThreadStatusServicoNFe);
end;
if Assigned(ThreadConsultaDFe) then
begin
  ThreadConsultaDFe.Terminate;
  ThreadConsultaDFe.WaitFor;
  FreeAndNil(ThreadConsultaDFe);
end;
FreeAndNil(CriticalStatusServicoNFe);
FreeAndNil(CriticalConsultaDFe);

end.
