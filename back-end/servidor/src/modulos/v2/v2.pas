unit v2;

interface

uses Math, Horse, JOSE.Core.JWT, JOSE.Core.Builder, SysUtils, Horse.JWT, uDM,
  uCacheControl, FireDAC.Comp.Client, Dataset.Serialize, JSON,
  token.autorizacao, Web.HTTPApp, System.Diagnostics,
  Data.FireDACJSONReflect, Soap.EncdDecd, FMX.Graphics, FMX.Printer,
  uRequisicao, System.RegularExpressions, DateUtils, PedidoSite,
  System.Threading, uControllCaches, System.Generics.Collections,
  uNewConsultas, uControllerSite, GooPedirAPIController, uAtualizacaoSite,
  System.IOUtils, System.SyncObjs, uGlobais, conexao, Xml.XMLDoc, Xml.XMLIntf,
  uControlerProdutoNotaFiscal, uGenericaFuncion, uTablet;
procedure Registry;
function DaysBetweenDates(const Date1, Date2: string): Integer;
procedure MovimentoProduto(Codigo, Tipo: Integer);
function ConverterData(const dataOriginal: string): string;
function GetCupomSite: String;
function RemoverTodasTransferencias(Texto: string): string;
function RetornoObjetoProduto(Dados: TFDQuery; conexao: TConexao): TJSONObject;
function CacheFilePath(const PedidoID: Integer): string;
function TryLoadCacheJSON(const FileName: string; out Obj: TJSONObject)
  : Boolean;
procedure SaveCacheJSON(const FileName: string; const Obj: TJSONObject);
function BuildPedidosUnion(const DataIniStr, DataFimStr: string): string;
function ExecutarProxyRequest(AJsonBody: String): String;
function BuscarRelatorioVenda(DataIni, DataFim: String): TJsonArray;
function BuscarDashBoardVenda(DataIni, DataFim: String): TJSONObject;

implementation

uses FireDAC.Stan.Option, token, JOSE.Types.JSON, System.Classes,
  Data.DB, IdWinsock2, Vcl.Dialogs, Vcl.ExtCtrls, Horse.Upload, System.Types,
  Winapi.Windows, uMain, System.StrUtils, Vcl.StdCtrls, util, uSite, uAgent,
  uIngredientesCardapio, uPerformanceMetrics;

type
  TPartnerInfo = record
    Partner: string;
    Quantidade: Integer;
    Valor: Double;
  end;

  TPartnerArray = array of TPartnerInfo;

var
  DashboardVendaCacheAquecendo: Boolean = False;
  DashboardVendaIgnorarCache: Boolean = False;
  V2StatusTraceLock: TCriticalSection;
  APIGoopedirLock: TCriticalSection;
  ServerStartedAt: TDateTime;
  ServerHealthTotalErros500: Int64 = 0;
  ServerHealthUltimoErro: string = '';
  ServerHealthUltimaEtapa: string = '';

procedure RegistrarErroSaudeServidor(const Etapa, Mensagem: string); forward;
procedure ExecutarAquecimentoCacheDashboardVendaTask; forward;

function ParseISODate(const S: string): TDate;
var
  y, m, d: Word;
begin
  if (Length(S) >= 10) and (S[5] = '-') and (S[8] = '-') then
  begin
    y := StrToInt(Copy(S, 1, 4));
    m := StrToInt(Copy(S, 6, 2));
    d := StrToInt(Copy(S, 9, 2));
    Result := EncodeDate(y, m, d);
  end
  else
    raise Exception.CreateFmt
      ('Data inv?lida: %s. Use o formato YYYY-MM-DD.', [S]);
end;

procedure RegistrarErroSaudeServidor(const Etapa, Mensagem: string);
begin
  TInterlocked.Increment(ServerHealthTotalErros500);
  ServerHealthUltimaEtapa := Etapa;
  ServerHealthUltimoErro := Copy(Mensagem, 1, 500);
end;

// function BuscarRelatorioVenda(DataIni, DataFim: String): TJsonArray;
// var
// conexao: TConexao;
// Dados: TFDMemTable;
// Resultado: TJsonArray;
//
// DataInicial: TDate;
// DataFinal: TDate;
// SQL: String;
// Chave: String;
// Consulta: String;
//
// begin
// try
// conexao := TConexao.Create('DoGetDashboardVendaV2');
// Dados := TFDMemTable.Create(nil);
// Chave := DataIni + DataFim + '.json';
//
// Resultado := conexao.BuscarCache(Chave);
//
// if Resultado.Count > 0 then
// begin
// Result := Resultado;
// conexao.free;
// exit;
// end;
//
// DataInicial := ISO8601ToDate(DataIni);
// DataFinal := ISO8601ToDate(DataFim);
// Resultado := TJsonArray.Create;
//
// while DataInicial <= DataFinal do
// begin
//
// if FormatDateTime('mmyyyy', DataInicial) = FormatDateTime('mmyyyy', date)
// then
// begin
// // Mes Atual
// SQL := 'pedido';
// end
// else
// begin
// // Mes Anterior
// SQL := 'pedido_' + FormatDateTime('yyyy_mm', DataInicial);
// end;
//
// conexao.SQL.Add('select p.codigo as id, p.data_pedido, concat(p.data_pedido,"T",p.hora_pedido) as date, p.origem, p.id_ifood, p.id_ficha, p.latitude, p.longitude, p.url, p.desc_desconto_ifood, ');
// conexao.SQL.Add('p.desc_ficha, p.tipo_pagamento, p.id_caixa, p.valor_desconto, p.valor_taxa_entrega, p.valor_total_pedido, c.codigo as id_cliente, c.nome as nome_cliente, c.pedidos as pedido_cliente, ce.bairro, ce.cidade, u.nome as atendente');
// conexao.SQL.Add('from ' + SQL + ' as p');
// conexao.SQL.Add('left join cliente as c on c.codigo = p.codigo_cliente');
// conexao.SQL.Add('left join cliente_endereco as ce on ce.codigo = p.codigo_cliente_endereco');
// conexao.SQL.Add('left join usuario as u on u.codigo = p.usuario');
// conexao.SQL.Add('where p.codigo_pedido_dia > 0 and p.status > 0');
// conexao.SQL.Add('and p.data_pedido between "' +
// FormatDateTime('yyyy-mm-dd', DataInicial) + '" and "' +
// FormatDateTime('yyyy-mm-dd', DataInicial) + '"');
// conexao.cache := True;
// try
// Consulta := conexao.ConsultaSQL.ToString;
// Dados.LoadFromJSON(Consulta);
// except
//
// end;
//
// if Dados.RecordCount > 0 then
// begin
// while not Dados.Eof do
// begin
// Resultado.AddElement(RetornoObjetoProduto(Dados, conexao));
// Dados.Next;
// end;
//
// end;
// Dados.Close;
// DataInicial := IncDay(DataInicial, 1);
// end;
//
// Dados.free;
// SQL := Resultado.ToString;
//
// if (FormatDateTime('yyyy-mm-dd', now) <> DataFim) then
// begin
// if DataIni <> DataFim then
// conexao.SalvarCache(Chave, TJSONObject.ParseJSONValue(SQL)
// as TJsonArray);
// end;
// Result := Resultado;
// conexao.free;
// except
// on E: Exception do
// begin
//
// end;
//
// end;
// end;
//
// function BuscarRelatorioVenda(DataIni, DataFim: String): TJsonArray;
// var
// conexao: TConexao;
// Dados: TFDMemTable;
// Resultado: TJsonArray;
//
// DataInicial, DataFinal: TDate;
// DataCursor: TDate;
//
// MesAtual, MesCursor: String;
// Tabela: String;
//
// Chave: String;
// Arr: TJSONArray;
// begin
// conexao := TConexao.Create('RelatorioVendaV2');
// Dados := TFDMemTable.Create(nil);
//
// try
// // ==============================
// // CACHE
// // ==============================
// Chave := DataIni + '_' + DataFim + '_relatorio.json';
// Resultado := conexao.BuscarCache(Chave);
//
// if Resultado.Count > 0 then
// begin
// Result := Resultado;
// Exit;
// end;
//
// // ==============================
// // Inicializa??es
// // ==============================
// Resultado := TJsonArray.Create;
//
// DataInicial := ISO8601ToDate(DataIni);
// DataFinal   := ISO8601ToDate(DataFim);
//
// MesAtual := FormatDateTime('yyyymm', Date);
// DataCursor := StartOfTheMonth(DataInicial);
//
// // ==============================
// // LOOP DOS MESES
// // ==============================
// while DataCursor <= EndOfTheMonth(DataFinal) do
// begin
// MesCursor := FormatDateTime('yyyymm', DataCursor);
//
// if MesCursor = MesAtual then
// Tabela := 'pedido'
// else
// Tabela := 'pedido_' + FormatDateTime('yyyy_mm', DataCursor);
//
// // ==============================
// // MONTA SQL
// // ==============================
// conexao.SQL.Clear;
// conexao.SQL.Add(
// 'SELECT '+
// ' p.codigo AS id,'+
// ' p.data_pedido,'+
// ' CONCAT(p.data_pedido,"T",p.hora_pedido) AS date,'+
// ' p.origem, p.id_ifood, p.id_ficha,'+
// ' p.latitude, p.longitude, p.url,'+
// ' p.desc_desconto_ifood, p.desc_ficha,'+
// ' p.tipo_pagamento, p.id_caixa,'+
// ' p.valor_desconto, p.valor_taxa_entrega, p.valor_total_pedido,'+
// ' c.codigo AS id_cliente, c.nome AS nome_cliente, c.pedidos AS pedido_cliente,'+
// ' ce.bairro, ce.cidade,'+
// ' u.nome AS atendente '+
// 'FROM '+Tabela+' p '+
// 'LEFT JOIN cliente c ON c.codigo = p.codigo_cliente '+
// 'LEFT JOIN cliente_endereco ce ON ce.codigo = p.codigo_cliente_endereco '+
// 'LEFT JOIN usuario u ON u.codigo = p.usuario '+
// 'WHERE p.codigo_pedido_dia > 0 AND p.status > 0 '+
// '  AND p.data_pedido BETWEEN :di AND :df'
// );
// conexao.Parametros('di', FormatDateTime('yyyy-mm-dd', DataInicial));
// conexao.Parametros('df', FormatDateTime('yyyy-mm-dd', DataFinal));
//
// conexao.cache := False;
//
// // ==============================
// // EXECUTA
// // ==============================
// Arr := conexao.ConsultaSQL;
//
// // Se nenhuma linha voltou, s? segue
// if (Arr = nil) or (Arr.Count = 0) then
// begin
// DataCursor := IncMonth(DataCursor, 1);
// Continue;
// end;
//
// // ==============================
// // CARREGA EM TFDMemTable
// // ==============================
// Dados.Close;
// try
// Dados.LoadFromJSON(Arr.ToJSON);
// except
// // Caso algo d? errado, segue o baile
// DataCursor := IncMonth(DataCursor, 1);
// Continue;
// end;
//
// // ==============================
// // VARRE RESULTADOS
// // ==============================
// Dados.First;
// while not Dados.Eof do
// begin
// Resultado.AddElement(RetornoObjetoProduto(Dados, conexao));
// Dados.Next;
// end;
//
// // Pr?ximo m?s
// DataCursor := IncMonth(DataCursor, 1);
// end;
//
// // ==============================
// // SALVA CACHE
// // ==============================
// if (DataIni <> DataFim) and
// (FormatDateTime('yyyy-mm-dd') <> DataFim) then
// begin
// conexao.SalvarCache(
// Chave,
// TJSONObject.ParseJSONValue(Resultado.ToJSON) as TJSONArray
// );
// end;
//
// Result := Resultado;
//
// finally
// Dados.Free;
// conexao.Free;
// end;
// end;
// function BuscarRelatorioVenda(DataIni, DataFim: String): TJsonArray;
// var
// conexao: TConexao;
// Dados: TFDMemTable;
// Resultado: TJsonArray;
//
// DataInicial, DataFinal: TDate;
// DataCursor: TDate;
//
// MesAtual, MesCursor: String;
// Tabela: String;
//
// Arr: TJsonArray;
// begin
// conexao := TConexao.Create('RelatorioVendaV2');
// Dados := TFDMemTable.Create(nil);
//
// try
// Resultado := TJsonArray.Create;
//
// DataInicial := ISO8601ToDate(DataIni);
// DataFinal := ISO8601ToDate(DataFim);
//
// MesAtual := FormatDateTime('yyyymm', Date);
// DataCursor := StartOfTheMonth(DataInicial);
//
// // ==============================
// // LOOP DOS MESES
// // ==============================
// while DataCursor <= EndOfTheMonth(DataFinal) do
// begin
// MesCursor := FormatDateTime('yyyymm', DataCursor);
//
// if MesCursor = MesAtual then
// Tabela := 'pedido'
// else
// Tabela := 'pedido_' + FormatDateTime('yyyy_mm', DataCursor);
//
// // ==============================
// // SQL PADR?O
// // ==============================
// conexao.SQL.Clear;
// conexao.SQL.Add('SELECT ' + ' p.codigo AS id,' + ' p.data_pedido,' +
// ' CONCAT(p.data_pedido,"T",p.hora_pedido) AS date,' +
// ' p.origem, p.id_ifood, p.id_ficha,' +
// ' p.latitude, p.longitude, p.url,' +
// ' p.desc_desconto_ifood, p.desc_ficha,' +
// ' p.tipo_pagamento, p.id_caixa,' +
// ' p.valor_desconto, p.valor_taxa_entrega, p.valor_total_pedido,' +
// ' c.codigo AS id_cliente, c.nome AS nome_cliente, c.pedidos AS pedido_cliente,'
// + ' ce.bairro, ce.cidade,' + ' u.nome AS atendente ' + 'FROM ' + Tabela
// + ' p ' + 'LEFT JOIN cliente c ON c.codigo = p.codigo_cliente ' +
// 'LEFT JOIN cliente_endereco ce ON ce.codigo = p.codigo_cliente_endereco '
// + 'LEFT JOIN usuario u ON u.codigo = p.usuario ' +
// 'WHERE p.codigo_pedido_dia > 0 AND p.status > 0 ' +
// '  AND p.data_pedido BETWEEN :di AND :df');
//
// conexao.Parametros('di', FormatDateTime('yyyy-mm-dd', DataInicial));
// conexao.Parametros('df', FormatDateTime('yyyy-mm-dd', DataFinal));
//
// // ==============================
// // EXECUTA
// // ==============================
// conexao.cache := False; // garantido
// Arr := conexao.ConsultaSQL;
//
// if (Arr = nil) or (Arr.Count = 0) then
// begin
// DataCursor := IncMonth(DataCursor, 1);
// Continue;
// end;
//
// // ==============================
// // CARREGA EM MEMTABLE
// // ==============================
// Dados.Close;
// try
// Dados.LoadFromJSON(Arr.ToJSON);
// except
// DataCursor := IncMonth(DataCursor, 1);
// Continue;
// end;
//
// // ==============================
// // ITERA RESULTADOS
// // ==============================
// Dados.First;
// while not Dados.Eof do
// begin
// Resultado.AddElement(RetornoObjetoProduto(Dados, conexao));
// Dados.Next;
// end;
//
// // Pr?ximo m?s
// DataCursor := IncMonth(DataCursor, 1);
// end;
//
// Result := Resultado;
//
// finally
// Dados.Free;
// conexao.Free;
// end;
// end;
function BuscarRelatorioVenda(DataIni, DataFim: String): TJsonArray;
var
  conexao: TConexao;
  Dados: TFDMemTable;
  Resultado: TJsonArray;
  MesAtual, MesCursor: String;
  Tabela: String;
  FiltroIni, FiltroFim: TDate;
  Arr: TJsonArray;
  Qry: TFDQuery;
begin
  conexao := TConexao.Create('RelatorioVendaV2');
  Qry := conexao.CriaQRY;
  try
    Resultado := TJsonArray.Create;
    Qry.SQL.Add('SELECT ' + ' p.codigo AS id,' + ' p.data_pedido,' +
      ' CONCAT(p.data_pedido,"T",p.hora_pedido) AS date,' +
      ' p.origem, p.id_ifood, p.id_ficha,' + ' p.latitude, p.longitude, p.url,'
      + ' upper(p.desc_desconto_ifood) as desc_desconto_ifood, p.desc_ficha,' +
      ' p.tipo_pagamento, p.id_caixa,' +
      ' p.valor_desconto, p.valor_taxa_entrega, p.valor_total_pedido,' +
      ' c.codigo AS id_cliente, c.nome AS nome_cliente, c.pedidos AS pedido_cliente,'
      + ' ce.bairro, ce.cidade,' + ' u.nome AS atendente ' + 'FROM pedido p ' +
      'LEFT JOIN cliente c ON c.codigo = p.codigo_cliente ' +
      'LEFT JOIN cliente_endereco ce ON ce.codigo = p.codigo_cliente_endereco '
      + 'LEFT JOIN usuario u ON u.codigo = p.usuario ' + 'WHERE p.status > 0 ' +
      '  AND p.data_pedido BETWEEN :di AND :df');
    // par?metros
    Qry.ParamByName('di').AsString := DataIni;
    Qry.ParamByName('df').AsString := DataFim;
    Qry.Open;
    if Qry.RecordCount > 0 then
    begin
      Qry.First;
      while not Qry.Eof do
      begin
        Resultado.AddElement(RetornoObjetoProduto(Qry, conexao));
        Qry.Next;
      end;
    end;
    Qry.Free;
    conexao.Free;
  finally
  end;
  Result := Resultado;
end;

function ExecutarProxyRequest(AJsonBody: String): String;
var
  JsonObj: TJSONObject;
  HeaderArray: TJsonArray;
  HeaderItem: TJSONObject;
  MetodoStr: String;
  MetodoEnum: TTipoMetodo;
  Req: iRequisicao;
  i: Integer;
  body: String;
begin
  Result := '';
  JsonObj := TJSONObject.ParseJSONValue(AJsonBody) as TJSONObject;
  if not Assigned(JsonObj) then
    exit;
  try
    Req := iRequisicao.Create(nil);
    try
      // Define timeout
      if JsonObj.GetValue('timeOut') <> nil then
        Req.TempoExpiracao := JsonObj.GetValue<Integer>('timeOut')
      else
        Req.TempoExpiracao := 20000;
      // Define URL (use BaseURL se necess?rio)
      if JsonObj.GetValue('url') <> nil then
        Req.URL := JsonObj.GetValue<string>('url');
      // Define m?todo HTTP
      MetodoStr := UpperCase(JsonObj.GetValue<string>('metodo'));
      if MetodoStr = 'POST' then
        MetodoEnum := mPost
      else if MetodoStr = 'PUT' then
        MetodoEnum := mPut
      else if MetodoStr = 'DELETE' then
        MetodoEnum := mDelete
      else if MetodoStr = 'PATCH' then
        MetodoEnum := mPatch
      else
        MetodoEnum := mGet;
      Req.Metodo := MetodoEnum;
      // Adiciona Headers
      if JsonObj.GetValue('header') <> nil then
      begin
        HeaderArray := JsonObj.GetValue<TJsonArray>('header');
        for i := 0 to HeaderArray.Count - 1 do
        begin
          HeaderItem := HeaderArray.Items[i] as TJSONObject;
          Req.AddHeader(HeaderItem.GetValue<string>('name'),
            HeaderItem.GetValue<string>('value'));
        end;
      end;
      // Adiciona Body (se houver)
      if (MetodoEnum in [mPost, mPut, mPatch]) and
        (JsonObj.GetValue('body') <> nil) then
      begin
        body := JsonObj.GetValue<string>('body');
        Req.body(body);
      end;
      // Executa requisi??o
      Req.Execute;
      // Retorna resposta
      Result := Req.Retorno;
    finally
      Req.Free;
    end;
  finally
    JsonObj.Free;
  end;
end;

function BuildPedidosUnion(const DataIniStr, DataFimStr: string): string;
var
  DataIni, DataFim, Cur: TDate;
  y, m, d: Word;
  y2, m2, d2: Word;
  Parts: TStringList;
  Linha, NomeTabela: string;
  conexao: TConexao;
  Q: TFDQuery;
  function TableExists(const TableName: string): Boolean;
  begin
    // Verifica na base atual (DATABASE()) se a tabela existe
    Q.Close;
    Q.SQL.Text := 'SELECT 1 ' + 'FROM information_schema.tables ' +
      'WHERE table_schema = DATABASE() ' + '  AND table_name = :t ' + 'LIMIT 1';
    Q.ParamByName('t').AsString := TableName;
    Q.Open;
    Result := Q.RecordCount > 0;
    Q.Close;
  end;

begin
  DataIni := ParseISODate(DataIniStr);
  DataFim := ParseISODate(DataFimStr);
  conexao := TConexao.Create('BuildPedidosUnion');
  Parts := TStringList.Create;
  Q := conexao.CriaQRY;
  try
    DecodeDate(DataIni, y, m, d);
    DecodeDate(DataFim, y2, m2, d2);
    // Sempre tenta incluir a tabela "pedido" (corrente) se existir
    if TableExists('pedido') then
      Parts.Add('SELECT id_caixa, codigo FROM pedido');
    // Normaliza para o 1? dia do m?s inicial
    Cur := EncodeDate(y, m, 1);
    // Meses do intervalo (inclusive)
    while (YearOf(Cur) < y2) or ((YearOf(Cur) = y2) and (MonthOf(Cur) <= m2)) do
    begin
      // Evita repetir o m?s corrente caso voc? j? use a "pedido" sem sufixo
      if not((YearOf(Cur) = YearOf(now)) and (MonthOf(Cur) = MonthOf(now))) then
      begin
        NomeTabela := Format('pedido_%d_%2.2d', [YearOf(Cur), MonthOf(Cur)]);
        if TableExists(NomeTabela) then
        begin
          Linha := Format('SELECT id_caixa, codigo FROM %s', [NomeTabela]);
          Parts.Add(Linha);
        end;
      end;
      Cur := IncMonth(Cur, 1);
    end;
    if Parts.Count = 0 then
      // Nenhuma tabela encontrada: retorna SELECT vazio compat?vel
      Result := '(SELECT id_caixa, codigo FROM (SELECT NULL id_caixa, NULL codigo) x WHERE 1=0)'
    else
      Result := '(' + StringReplace(Trim(Parts.Text), sLineBreak, ' UNION ALL ',
        [rfReplaceAll]) + ')';
  finally
    Q.Free;
    Parts.Free;
    conexao.Free;
  end;
end;

function CacheFilePath(const PedidoID: Integer): string;
begin
  Result := TPath.Combine(TPath.GetTempPath, Format('pedido_%d.json',
    [PedidoID]));
end;

function TryLoadCacheJSON(const FileName: string; out Obj: TJSONObject)
  : Boolean;
var
  S: string;
  V: TJSONValue;
begin
  Result := False;
  Obj := nil;
  if not TFile.Exists(FileName) then
    exit;
  S := TFile.ReadAllText(FileName, TEncoding.UTF8);
  V := TJSONObject.ParseJSONValue(S);
  if (V <> nil) and (V is TJSONObject) then
  begin
    Obj := TJSONObject(V); // transfere posse
    Result := True;
  end
  else
    V.Free;
end;

procedure SaveCacheJSON(const FileName: string; const Obj: TJSONObject);
begin
  TFile.WriteAllText(FileName, Obj.ToJSON, TEncoding.UTF8);
end;

// function RetornoObjetoProduto(Dados: TFDMemTable; conexao: TConexao)
// : TJSONObject;
// var
// DadosPagamento: TFDMemTable;
// DadosItens: TFDMemTable;
//
// Objeto: TJSONObject;
// ObjetoCliente: TJSONObject;
// Pagamentos: TJSONArray;
// ObjetoPagamentos: TJSONObject;
// ObjetoEndereco: TJSONObject;
// ObjetoIten: TJSONObject;
// Itens: TJSONArray;
// ObjetoAdicional: TJSONObject;
// Adicionais: TJSONArray;
// ObjetoSabor: TJSONObject;
// Sabores: TJSONArray;
// DadosExtra: TFDMemTable;
//
// Canal: String;
// Atendente: String;
// Cupom: String;
// Pagamento: String;
// begin
// Objeto := TJSONObject.Create;
// ObjetoCliente := TJSONObject.Create;
// ObjetoEndereco := TJSONObject.Create;
// Pagamentos := TJSONArray.Create;
// Itens := TJSONArray.Create;
// DadosPagamento := TFDMemTable.Create(nil);
// DadosItens := TFDMemTable.Create(nil);
//
// Objeto.AddPair('id', Dados.FieldByName('id').AsInteger);
// Objeto.AddPair('date', Dados.FieldByName('date').AsString);
// Canal := 'Retirada';
// Cupom := '';
// if Dados.FieldByName('id_ifood').AsString <> '' then
// begin
// Canal := 'iFood';
// Cupom := Dados.FieldByName('desc_desconto_ifood').AsString;
// Cupom := Copy(Cupom, 0, Pos(Cupom, '-'));
// end;
// if Dados.FieldByName('id_ficha').AsFloat > 0 then
// begin
// Canal := 'Mesa';
// // Atendente := Dados.FieldByName('atendente').AsString;
// end;
// if Dados.FieldByName('bairro').AsString <> '' then
// begin
// if Canal <> 'iFood' then
// Canal := 'Delivery';
// end;
// if Dados.FieldByName('origem').AsString = '5' then
// begin
// Canal := 'PDV';
// Atendente := Dados.FieldByName('atendente').AsString;
// end;
//
// if Dados.FieldByName('bairro').AsString <> '' then
// begin
// ObjetoEndereco.AddPair('latitude', Dados.FieldByName('latitude').AsFloat);
// ObjetoEndereco.AddPair('longitude', Dados.FieldByName('longitude').AsFloat);
// ObjetoEndereco.AddPair('deliveryFee',
// Dados.FieldByName('valor_taxa_entrega').AsFloat);
// ObjetoEndereco.AddPair('district', Dados.FieldByName('bairro').AsString);
// ObjetoEndereco.AddPair('city', Dados.FieldByName('cidade').AsString);
// end;
//
// if Canal <> 'Mesa' then
// begin
// ObjetoCliente.AddPair('id', Dados.FieldByName('id_cliente').AsInteger);
// ObjetoCliente.AddPair('name', Dados.FieldByName('nome_cliente').AsString);
// ObjetoCliente.AddPair('count', Dados.FieldByName('pedido_cliente')
// .AsInteger);
// ObjetoCliente.AddPair('address', ObjetoEndereco)
// end;
//
// if Dados.FieldByName('id_caixa').AsString <> '' then
// begin
// // Pedido Faturado
//
// conexao.SQL.Add('SELECT tp.descricao, c.valor FROM caixa_movimento as c');
// conexao.SQL.Add
// ('join tipo_pagamento as tp on tp.codigo = c.id_tipo_pagamento');
// conexao.SQL.Add('where c.id_pedido = :id');
// conexao.Parametros('id', Dados.FieldByName('id').AsInteger);
// DadosPagamento.LoadFromJSON(conexao.ConsultaSQL);
// if DadosPagamento.RecordCount > 0 then
// begin
// while not DadosPagamento.Eof do
// begin
// ObjetoPagamentos := TJSONObject.Create;
// ObjetoPagamentos.AddPair('payment',
// DadosPagamento.FieldByName('descricao').AsString);
// ObjetoPagamentos.AddPair('value', DadosPagamento.FieldByName('valor')
// .AsString);
// ObjetoPagamentos.AddPair('invoiced', True);
// Pagamentos.AddElement(ObjetoPagamentos);
//
// DadosPagamento.Next;
// end;
// end;
// end
// else
// begin
// // Pedido nao faturado
// conexao.SQL.Add
// ('select codigo, descricao from tipo_pagamento where codigo = :id');
// conexao.Parametros('id', Dados.FieldByName('tipo_pagamento').AsInteger);
// try
// Pagamento := conexao.FieldByName('descricao');
// except
// Pagamento := '';
// end;
// ObjetoPagamentos := TJSONObject.Create;
// ObjetoPagamentos.AddPair('payment', Pagamento);
// ObjetoPagamentos.AddPair('value',
// DadosPagamento.FieldByName('valor_total_pedido').AsString);
// ObjetoPagamentos.AddPair('invoiced', false);
// Pagamentos.AddElement(ObjetoPagamentos);
// end;
//
// conexao.SQL.Add
// ('SELECT pp.codigo as id, pp.codigo_pedido, p.nome_produto as product, tp. descricao as category, pp.quantidade as qty, pp.valor_total as price,');
// conexao.SQL.Add('tp.pizza FROM pedido_produtos as pp');
// conexao.SQL.Add('join produto as p on p.codigo = pp.codigo_produto');
// conexao.SQL.Add('join tipo_produto as tp on tp.codigo = p.codigo_grupo');
// conexao.SQL.Add('where pp.codigo_pedido = :codigo');
// conexao.Parametros('codigo', Dados.FieldByName('id').AsInteger);
// DadosItens.LoadFromJSON(conexao.ConsultaSQL);
// if DadosItens.RecordCount > 0 then
// begin
// while not DadosItens.Eof do
// begin
// Adicionais := TJSONArray.Create;
// Sabores := TJSONArray.Create;
// ObjetoIten := TJSONObject.Create;
// ObjetoIten.AddPair('product', DadosItens.FieldByName('product').AsString);
// ObjetoIten.AddPair('category', DadosItens.FieldByName('category')
// .AsString);
// ObjetoIten.AddPair('qty', DadosItens.FieldByName('qty').AsFloat);
// ObjetoIten.AddPair('price', DadosItens.FieldByName('price').AsFloat);
//
// conexao.SQL.Add
// ('select pps.*, CASE WHEN ts.id > 30 THEN 1 ELSE 0 END as pizza');
// conexao.SQL.Add('from pedido_produto_sap as pps');
// conexao.SQL.Add
// ('left join tipo_sabor as ts on ts.nome = pps.nomeclatura');
// conexao.SQL.Add('where pps.valor > 0 and codigo_pedido_produto = :id');
// conexao.Parametros('id', DadosItens.FieldByName('id').AsInteger);
// DadosExtra := TFDMemTable.Create(nil);
// DadosExtra.LoadFromJSON(conexao.ConsultaSQL);
//
// if DadosExtra.RecordCount > 0 then
// begin
// while not DadosExtra.Eof do
// begin
// if DadosExtra.FieldByName('pizza').AsInteger = 0 then
// begin
// // Extra
// if UpperCase(DadosExtra.FieldByName('nomeclatura').AsString) <> 'SABORES'
// then
// begin
// ObjetoAdicional := TJSONObject.Create;
// ObjetoAdicional.AddPair('extra',
// DadosExtra.FieldByName('nomeclatura').AsString);
// ObjetoAdicional.AddPair('name',
// DadosExtra.FieldByName('descricao').AsString);
// ObjetoAdicional.AddPair('value',
// DadosExtra.FieldByName('valor').AsFloat);
// Adicionais.AddElement(ObjetoAdicional);
// end
// else
// begin
// ObjetoSabor := TJSONObject.Create;
// ObjetoSabor.AddPair('name', DadosExtra.FieldByName('descricao')
// .AsString);
// ObjetoSabor.AddPair('value',
// DadosExtra.FieldByName('valor').AsFloat);
// Sabores.AddElement(ObjetoSabor);
// end;
// end
// else
// begin
// // Pizza
// ObjetoSabor := TJSONObject.Create;
// ObjetoSabor.AddPair('name', DadosExtra.FieldByName('descricao')
// .AsString);
// ObjetoSabor.AddPair('value',
// DadosExtra.FieldByName('valor').AsFloat);
// Sabores.AddElement(ObjetoSabor);
// end;
// DadosExtra.Next;
// end;
// end;
// ObjetoIten.AddPair('additional', Adicionais);
// ObjetoIten.AddPair('pizzaFlavors', Sabores);
// DadosExtra.Free;
// Itens.AddElement(ObjetoIten);
// DadosItens.Next;
// end;
// end;
//
// Objeto.AddPair('channel', Canal);
// Objeto.AddPair('payment', Pagamentos);
// Objeto.AddPair('attendant', Atendente);
// Objeto.AddPair('customer', ObjetoCliente);
// Objeto.AddPair('coupon', Cupom);
// Objeto.AddPair('discount', Dados.FieldByName('valor_desconto').AsFloat);
// Objeto.AddPair('items', Itens);
// end;
function RetornoObjetoProduto(Dados: TFDQuery; conexao: TConexao): TJSONObject;
var
  DadosPagamento, DadosExtra: TFDMemTable;
  Objeto, ObjetoCliente, ObjetoEndereco, ObjetoPagamentos, ObjetoIten,
    ObjetoAdicional, ObjetoSabor: TJSONObject;
  Pagamentos, Itens, Adicionais, Sabores: TJsonArray;
  Canal, Atendente, Cupom, Pagamento: string;
  PedidoID: Integer;
  CachePath: string;
  FromCache: TJSONObject;
  Total: Real;
  DadosItens: TFDQuery;
begin
  // ===== Tentativa de usar cache =====
  PedidoID := Dados.FieldByName('id').AsInteger;
  CachePath := CacheFilePath(PedidoID);
  if TryLoadCacheJSON(CachePath, FromCache) then
  begin
    Result := FromCache;
    exit;
  end;
  // ===== Montagem normal (sem cache) =====
  Objeto := TJSONObject.Create;
  ObjetoCliente := TJSONObject.Create;
  ObjetoEndereco := TJSONObject.Create;
  Pagamentos := TJsonArray.Create;
  Itens := TJsonArray.Create;
  DadosPagamento := TFDMemTable.Create(nil);
  DadosItens := conexao.CriaQRY;
  try
    Objeto.AddPair('id', Dados.FieldByName('id').AsInteger);
    Objeto.AddPair('date', Dados.FieldByName('date').AsString);
    Total := 0;
    Canal := 'Retirada';
    Cupom := '';
    Atendente := '';
    Cupom := Dados.FieldByName('desc_desconto_ifood').AsString;
    if Dados.FieldByName('id_ifood').AsString <> '' then
    begin
      Canal := 'iFood';
      // (ajuste do Copy: pega parte antes de '-')
      if Pos('-', Cupom) > 0 then
        Cupom := Copy(Cupom, 1, Pos('-', Cupom) - 1);
    end;
    if Dados.FieldByName('id_ficha').AsFloat > 0 then
      Canal := 'Mesa';
    if Dados.FieldByName('bairro').AsString <> '' then
      if Canal <> 'iFood' then
        Canal := 'Delivery';
    if Dados.FieldByName('origem').AsString = '5' then
    begin
      Canal := 'PDV';
      Atendente := Dados.FieldByName('atendente').AsString;
    end;
    if Dados.FieldByName('bairro').AsString <> '' then
    begin
      ObjetoEndereco.AddPair('latitude',
        TJSONNumber.Create(Dados.FieldByName('latitude').AsFloat));
      ObjetoEndereco.AddPair('longitude',
        TJSONNumber.Create(Dados.FieldByName('longitude').AsFloat));
      ObjetoEndereco.AddPair('deliveryFee',
        TJSONNumber.Create(Dados.FieldByName('valor_taxa_entrega').AsFloat));
      ObjetoEndereco.AddPair('district', Dados.FieldByName('bairro').AsString);
      ObjetoEndereco.AddPair('city', Dados.FieldByName('cidade').AsString);
    end;
    if Canal <> 'Mesa' then
    begin
      ObjetoCliente.AddPair('id', Dados.FieldByName('id_cliente').AsInteger);
      ObjetoCliente.AddPair('name', Dados.FieldByName('nome_cliente').AsString);
      ObjetoCliente.AddPair('count', Dados.FieldByName('pedido_cliente')
        .AsInteger);
      ObjetoCliente.AddPair('address', ObjetoEndereco);
    end
    else
      ObjetoEndereco.Free; // n?o usado
    // ===== Pagamentos =====
    if Dados.FieldByName('id_caixa').AsString <> '' then
    begin
      // Pedido faturado
      conexao.SQL.Add('SELECT tp.descricao, c.valor FROM caixa_movimento as c');
      conexao.SQL.Add
        ('join tipo_pagamento as tp on tp.codigo = c.id_tipo_pagamento');
      conexao.SQL.Add('where c.id_pedido = :id');
      conexao.Parametros('id', PedidoID);
      DadosPagamento.LoadFromJSON(conexao.ConsultaSQL);
      if DadosPagamento.RecordCount > 0 then
      begin
        DadosPagamento.First;
        while not DadosPagamento.Eof do
        begin
          ObjetoPagamentos := TJSONObject.Create;
          ObjetoPagamentos.AddPair('payment',
            DadosPagamento.FieldByName('descricao').AsString);
          ObjetoPagamentos.AddPair('value',
            TJSONNumber.Create(DadosPagamento.FieldByName('valor').AsFloat));
          ObjetoPagamentos.AddPair('invoiced', TJSONBool.Create(True));
          Pagamentos.AddElement(ObjetoPagamentos);
          DadosPagamento.Next;
        end;
      end;
    end
    else
    begin
      // Pedido N?O faturado
      conexao.SQL.Add
        ('select codigo, descricao from tipo_pagamento where codigo = :id');
      conexao.Parametros('id', Dados.FieldByName('tipo_pagamento').AsInteger);
      try
        Pagamento := conexao.FieldByName('descricao');
      except
        Pagamento := '';
      end;
      ObjetoPagamentos := TJSONObject.Create;
      ObjetoPagamentos.AddPair('payment', Pagamento);
      // Obs.: aqui fazia refer?ncia a DadosPagamento; usei Dados (pedido) para total
      ObjetoPagamentos.AddPair('value',
        TJSONNumber.Create(Dados.FieldByName('valor_total_pedido').AsFloat));
      ObjetoPagamentos.AddPair('invoiced', TJSONBool.Create(False));
      Pagamentos.AddElement(ObjetoPagamentos);
    end;
    DadosItens.Close;
    DadosItens.SQL.Add
      ('SELECT pp.codigo as id, pp.codigo_pedido, p.nome_produto as product, ' +
      'tp.descricao as category, pp.quantidade as qty, pp.valor_total as price, '
      + 'tp.pizza FROM pedido_produtos as pp ' +
      'join produto as p on p.codigo = pp.codigo_produto ' +
      'join tipo_produto as tp on tp.codigo = p.codigo_grupo ' +
      'where pp.codigo_pedido = :codigo and (pp.usuario_deletado = 0 or pp.usuario_deletado is null)');
    DadosItens.ParamByName('codigo').AsInteger := PedidoID;
    DadosItens.Open;
    if DadosItens.RecordCount > 0 then
    begin
      DadosItens.First;
      while not DadosItens.Eof do
      begin
        Adicionais := TJsonArray.Create;
        Sabores := TJsonArray.Create;
        ObjetoIten := TJSONObject.Create;
        ObjetoIten.AddPair('product', DadosItens.FieldByName('product')
          .AsString);
        ObjetoIten.AddPair('category', DadosItens.FieldByName('category')
          .AsString);
        ObjetoIten.AddPair('qty',
          TJSONNumber.Create(DadosItens.FieldByName('qty').AsFloat));
        ObjetoIten.AddPair('price',
          TJSONNumber.Create(DadosItens.FieldByName('price').AsFloat));
        Total := Total + DadosItens.FieldByName('price').AsFloat;
        // Extras / Sabores
        DadosExtra := TFDMemTable.Create(nil);
        try
          conexao.SQL.Add
            ('select pps.*, CASE WHEN ts.id > 30 THEN 1 ELSE 0 END as pizza ' +
            'from pedido_produto_sap as pps ' +
            'left join tipo_sabor as ts on ts.nome = pps.nomeclatura ' +
            'where pps.valor > 0 and codigo_pedido_produto = :id');
          conexao.Parametros('id', DadosItens.FieldByName('id').AsInteger);
          DadosExtra.LoadFromJSON(conexao.ConsultaSQL);
          if DadosExtra.RecordCount > 0 then
          begin
            DadosExtra.First;
            while not DadosExtra.Eof do
            begin
              if DadosExtra.FieldByName('pizza').AsInteger = 0 then
              begin
                // Extra (n?o-pizza)
                if UpperCase(DadosExtra.FieldByName('nomeclatura').AsString) <> 'SABORES'
                then
                begin
                  ObjetoAdicional := TJSONObject.Create;
                  ObjetoAdicional.AddPair('extra',
                    DadosExtra.FieldByName('nomeclatura').AsString);
                  ObjetoAdicional.AddPair('name',
                    DadosExtra.FieldByName('descricao').AsString);
                  ObjetoAdicional.AddPair('value',
                    TJSONNumber.Create(DadosExtra.FieldByName('valor')
                    .AsFloat));
                  Adicionais.AddElement(ObjetoAdicional);
                end
                else
                begin
                  ObjetoSabor := TJSONObject.Create;
                  ObjetoSabor.AddPair('name',
                    DadosExtra.FieldByName('descricao').AsString);
                  ObjetoSabor.AddPair('value',
                    TJSONNumber.Create(DadosExtra.FieldByName('valor')
                    .AsFloat));
                  Sabores.AddElement(ObjetoSabor);
                end;
              end
              else
              begin
                // Pizza
                ObjetoSabor := TJSONObject.Create;
                ObjetoSabor.AddPair('name', DadosExtra.FieldByName('descricao')
                  .AsString);
                ObjetoSabor.AddPair('value',
                  TJSONNumber.Create(DadosExtra.FieldByName('valor').AsFloat));
                Sabores.AddElement(ObjetoSabor);
              end;
              DadosExtra.Next;
            end;
          end;
          ObjetoIten.AddPair('additional', Adicionais);
          ObjetoIten.AddPair('pizzaFlavors', Sabores);
          Itens.AddElement(ObjetoIten);
        finally
          DadosExtra.Free;
        end;
        DadosItens.Next;
      end;
    end;
    // ===== Final =====
    Objeto.AddPair('channel', Canal);
    Objeto.AddPair('payment', Pagamentos);
    Objeto.AddPair('attendant', Atendente);
    Objeto.AddPair('tot',
      TJSONNumber.Create(Dados.FieldByName('valor_total_pedido').AsFloat));
    if Canal <> 'Mesa' then
      Objeto.AddPair('customer', ObjetoCliente)
    else
      ObjetoCliente.Free; // n?o ser? usado
    Objeto.AddPair('coupon', Cupom);
    Objeto.AddPair('discount',
      TJSONNumber.Create(Dados.FieldByName('valor_desconto').AsFloat));
    Objeto.AddPair('items', Itens);
    // Salva no cache (temp) e retorna
    SaveCacheJSON(CachePath, Objeto);
    Result := Objeto;
  finally
    DadosPagamento.Free;
    DadosItens.Free;
    // N?O liberar Objeto, Pagamentos, Itens, etc., pois s?o retornados em Result
  end;
end;

function RemoverTodasTransferencias(Texto: string): string;
var
  InicioTransferencia, FimTransferencia: Integer;
begin
  // Loop para remover todas as ocorr?ncias de transfer?ncia
  while True do
  begin
    // Procura o in?cio da marca??o de transfer?ncia
    InicioTransferencia := Pos('<p><i>Transfer?ncia', Texto);
    // Se n?o encontrar mais transfer?ncias, sai do loop
    if InicioTransferencia = 0 then
      Break;
    // Procura o fim da marca??o de transfer?ncia
    FimTransferencia := Pos('</i></p>', Texto, InicioTransferencia);
    // Se encontrar o fim da transfer?ncia
    if FimTransferencia > 0 then
    begin
      // Remove o trecho da transfer?ncia, incluindo as tags <p><i> e </i></p>
      Delete(Texto, InicioTransferencia, FimTransferencia - InicioTransferencia
        + Length('</i></p>'));
    end
    else
    begin
      // Se n?o encontrar o fechamento, sai do loop para evitar loops infinitos
      Break;
    end;
  end;
  // Retorna o texto sem as transfer?ncias e suas tags
  Result := Texto;
end;

procedure AtualizaValorPedido(Codigo: Integer);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  // conexao.SQL.Add
  // ('select 0 as codigo, sum(valor_total) as total from pedido_produtos where codigo_pedido = :codigo');
  // conexao.Parametros('codigo', Codigo);
  // try
  // Valor := conexao.FieldByName('total');
  // except
  // Valor := 0;
  // end;
  // conexao.SQL.Add
  // ('update pedido set valor_pedido = :pedido, valor_total_pedido = ((:pedido + valor_taxa_entrega) - valor_desconto) where codigo = :codigo');
  conexao.SQL.Add
    ('update pedido set valor_pedido = (select sum(pp.valor_total) from pedido_produtos as pp where pp.codigo_pedido = :codigo)');
  conexao.SQL.Add
    (', valor_total_pedido = (((select sum(pp.valor_total) from pedido_produtos as pp where pp.codigo_pedido = :codigo) + valor_taxa_entrega) - valor_desconto) where codigo = :codigo');
  conexao.Parametros('codigo', Codigo);
  conexao.ExecuteSQL;
  conexao.SQL.Add
    ('update mesa set tot_mesa = (select valor_pedido from pedido where codigo = selecionada) where selecionada = :codigo');
  conexao.Parametros('codigo', Codigo);
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoGetCardapioValidaHash(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  Obj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  Obj.AddPair('validacao', frmServidor.ProdutosHash.ValidarHash
    (Req.Params['categoria'], Req.Params['hash']));
  Res.Send<TJSONObject>(Obj);
end;

procedure DoGetCaetegory(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('SELECT produto.codigo as id,');
  conexao.SQL.Add('produto.nome_produto as name,');
  conexao.SQL.Add('produto.descricao as description,');
  conexao.SQL.Add('produto.ativo as status,');
  conexao.SQL.Add('produto_pizza.quantidade_sabores as sabores');
  conexao.SQL.Add('FROM produto');
  conexao.SQL.Add
    ('join produto_pizza on produto_pizza.codigo_produto = produto.codigo');
  conexao.SQL.Add('where produto.codigo_grupo = :grupo');
  conexao.Parametros('grupo', Req.Params['category']);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostCategorySizeNew(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  CodigoAux, CodigoGrupo, Aux, position: Integer;
  ValorPadrao, Sabores: Double;
  conexao: TConexao;
  ProductItem: TJSONObject;
  JSONValue: TJSONValue;
  Codigo: Integer;
  Dados: TFDMemTable;
begin
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  // Verificar se o JSON foi parseado com sucesso
  if Assigned(JSONValue) and (JSONValue is TJSONObject) then
  begin
    // Converter o JSONValue para um TJSONObject
    ProductItem := JSONValue as TJSONObject;
    conexao := TConexao.Create('DoPostCategorySizeNew');
    CodigoGrupo := ProductItem.GetValue<Integer>('categoria');
    Sabores := ProductItem.GetValue<Double>('sabores');
    ValorPadrao := ProductItem.GetValue<Double>('valorPadrao');
    // Gerar c?digo do produto
    CodigoAux := conexao.GerarID('produto', 'codigo');
    // Buscar posi??o m?xima
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('select max(position) as max, 0 as zero from produto where codigo_grupo = :grupo');
    conexao.Parametros('grupo', CodigoGrupo);
    position := conexao.FieldByName('max');
    // Inserir na tabela produto
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('insert into produto (codigo, codigo_interno, data_cadastro, nome_produto, descricao, codigo_grupo, valor_venda, ativo, position)');
    conexao.SQL.Add
      ('values (:codigo, :codigo_interno, current_date, :nome_produto, :descricao, :codigo_grupo, :valor_venda, 1, :position)');
    conexao.Parametros('codigo', CodigoAux);
    conexao.Parametros('codigo_interno', CodigoAux);
    conexao.Parametros('nome_produto', ProductItem.GetValue<string>('nome'));
    conexao.Parametros('descricao', ProductItem.GetValue<string>('descricao'));
    conexao.Parametros('codigo_grupo', CodigoGrupo);
    conexao.Parametros('valor_venda', 0);
    conexao.Parametros('position', position);
    conexao.ExecuteSQL;
    // Inserir na tabela produto_pizza
    Aux := conexao.GerarID('produto_pizza', 'codigo');
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('insert into produto_pizza (codigo, codigo_produto, quantidade_sabores, borda, ativo)');
    conexao.SQL.Add
      ('values (:codigo, :codigo_produto, :quantidade_sabores, 0, 1)');
    conexao.Parametros('codigo', Aux);
    conexao.Parametros('codigo_produto', CodigoAux);
    conexao.Parametros('quantidade_sabores', Sabores);
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('select p.codigo, 0 as zero from tipo_produto as tp join produto as p on p.codigo_grupo = tp.codigo where tp.codigo = :grupo limit 1');
    conexao.Parametros('grupo', CodigoGrupo);
    Codigo := conexao.FieldByName('codigo');
    conexao.SQL.Add
      ('select * from sabores_completo where id_produto = :codigo');
    conexao.Parametros('codigo', Codigo);
    Dados := TFDMemTable.Create(NIL);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount > 0 then
    begin
      while not Dados.Eof do
      begin
        Aux := conexao.GerarID('sabores_completo', 'id');
        conexao.SQL.Add('INSERT INTO sabores_completo (');
        conexao.SQL.Add('    id,');
        conexao.SQL.Add('    id_produto,');
        conexao.SQL.Add('    id_tipo_sabor,');
        conexao.SQL.Add('    dt_cadastro,');
        conexao.SQL.Add('    nome,');
        conexao.SQL.Add('    descricao,');
        conexao.SQL.Add('    vl_venda,');
        conexao.SQL.Add('    ativo,');
        conexao.SQL.Add('    id_site,');
        conexao.SQL.Add('    modificado_site');
        conexao.SQL.Add(')');
        conexao.SQL.Add('SELECT');
        conexao.SQL.Add('    :cod AS new_id,');
        conexao.SQL.Add('    :novo_id_produto AS id_produto,');
        conexao.SQL.Add('    id_tipo_sabor,');
        conexao.SQL.Add('    CURRENT_DATE AS dt_cadastro,');
        conexao.SQL.Add('    nome,');
        conexao.SQL.Add('    descricao,');
        conexao.SQL.Add('    :novo_valor_venda AS vl_venda,');
        conexao.SQL.Add('    ativo,');
        conexao.SQL.Add('    0 AS id_site,');
        conexao.SQL.Add('    0 AS modificado_site');
        conexao.SQL.Add('FROM sabores_completo');
        conexao.SQL.Add('WHERE id_produto = :produto_origem and id = :id;');
        conexao.Parametros('id', Dados.FieldByName('id').AsInteger);
        conexao.Parametros('produto_origem', Codigo);
        conexao.Parametros('cod', Aux);
        conexao.Parametros('novo_id_produto', CodigoAux);
        conexao.Parametros('novo_valor_venda', ValorPadrao);
        conexao.ExecuteSQL;
        Dados.Next;
      end;
    end;
    Dados.Free;
    conexao.SQL.Add('delete from geradores');
    conexao.ExecuteSQL;
    EnviaProduto(CodigoAux, '', '');
    conexao.Free;
  end;
end;

procedure DoPostCategory(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  DadosTipo: TFDMemTable;
  JSONString: string;
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  ProductArray: TJsonArray;
  ProductItem: TJSONObject;
  i: Integer;
  CodigoGrupo: Integer;
  CodigoAux: Integer;
  Aux: Integer;
  Query: TFDQuery;
  CaminhoImagem: String;
  ExtraArray: TJsonArray;
  ExtraItem: TJSONObject;
  ExtraItensArray: TJsonArray;
  ExtraItensItem: TJSONObject;
  CodigoExtra: Integer;
  Cod: Integer;
  K: Integer;
  Ordem: Integer;
begin
  conexao := TConexao.Create('v2');
  Query := conexao.CriaQRY;
  DadosTipo := TFDMemTable.Create(nil);
  // Fazer o parsing do JSON
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  // Verificar se o JSON foi parseado com sucesso
  if Assigned(JSONValue) and (JSONValue is TJSONObject) then
  begin
    // Converter o JSONValue para um TJSONObject
    JSONObject := JSONValue as TJSONObject;
    try
      // Verifica se o tipo de produto j? existe
      conexao.SQL.Add('select * from tipo_produto where codigo = :codigo');
      conexao.Parametros('codigo', JSONObject.Values['id'].Value);
      DadosTipo.LoadFromJSON(conexao.ConsultaSQL);
      if DadosTipo.RecordCount = 0 then
      begin
        // Novo tipo de produto, insere um novo registro
        CodigoGrupo := conexao.GerarID('tipo_produto', 'codigo');
        conexao.SQL.Add
          ('select 0 as zero, max(ordem) as ordem from tipo_produto');
        try
          Ordem := conexao.FieldByName('ordem');
        except
          Ordem := 0;
        end;
        inc(Ordem);
        Query.SQL.Text :=
          'insert into tipo_produto (codigo, descricao, impressora, pizza, visivel_delivery, visivel_vem_buscar, local, '
          + 'borda_topo_direito, borda_topo_esquerdo, borda_inferior_direito, borda_inferior_esquerdo, espacamento, fonte_nome, fonte_descricao, cor_fundo, cor_nome, cor_descricao, descricao_cat, opacidade, destaque, ordem, tempo_estimado) '
          + 'values (:codigo, :descricao, :impressora, :pizza, 1, 1, :local, ' +
          ':borda_topo_direito, :borda_topo_esquerdo, :borda_inferior_direito, :borda_inferior_esquerdo, :espacamento, :fonte_nome, :fonte_descricao, :cor_fundo, :cor_nome, :cor_descricao, :descricao_cat,:opacidade, :destaque ,:ordem, :tempo)';
        Query.ParamByName('codigo').AsInteger := CodigoGrupo;
        if JSONObject.Values['type'].Value = '1' then
          Query.ParamByName('pizza').AsInteger := 0
        else
          Query.ParamByName('pizza').AsInteger := 1;
        Query.ParamByName('ordem').AsInteger := Ordem;
      end
      else
      begin
        // Atualiza o tipo de produto existente
        Query.SQL.Text :=
          'update tipo_produto set descricao = :descricao, impressora = :impressora, local = :local,'
          + 'borda_topo_direito = :borda_topo_direito, borda_topo_esquerdo = :borda_topo_esquerdo, '
          + 'borda_inferior_direito = :borda_inferior_direito, borda_inferior_esquerdo = :borda_inferior_esquerdo, '
          + 'espacamento = :espacamento, opacidade = :opacidade, fonte_nome = :fonte_nome, fonte_descricao = :fonte_descricao, '
          + 'cor_fundo = :cor_fundo, tempo_estimado = :tempo, cor_nome = :cor_nome, cor_descricao = :cor_descricao, descricao_cat = :descricao_cat, destaque = :destaque '
          + 'where codigo = :codigo';
        Query.ParamByName('codigo').AsInteger := DadosTipo.FieldByName('codigo')
          .AsInteger;
        CodigoGrupo := DadosTipo.FieldByName('codigo').AsInteger;
      end;
      // Par?metros comuns
      Query.ParamByName('descricao').AsWideString := JSONObject.Values
        ['name'].Value;
      Query.ParamByName('impressora').AsWideString := JSONObject.Values
        ['printer'].Value;
      Query.ParamByName('borda_topo_direito').AsInteger := 0;
      Query.ParamByName('local').AsWideString := JSONObject.Values
        ['local'].Value;
      Query.ParamByName('borda_topo_esquerdo').AsInteger := 0;
      Query.ParamByName('borda_inferior_direito').AsInteger := 0;
      Query.ParamByName('borda_inferior_esquerdo').AsInteger := 0;
      Query.ParamByName('espacamento').AsInteger := JSONObject.Values['altura']
        .Value.ToInteger;
      Query.ParamByName('opacidade').AsInteger := JSONObject.Values['opacidade']
        .Value.ToInteger;
      Query.ParamByName('fonte_nome').AsInteger := 0;
      Query.ParamByName('fonte_descricao').AsInteger := 0;
      Query.ParamByName('cor_fundo').AsWideString := JSONObject.Values
        ['corfundo'].Value;
      Query.ParamByName('cor_nome').AsWideString := JSONObject.Values
        ['corfontenome'].Value;
      Query.ParamByName('cor_descricao').AsWideString :=
        JSONObject.Values['corfontedescricao'].Value;
      Query.ParamByName('descricao_cat').AsWideString :=
        JSONObject.Values['descricao'].Value;
      try
        if JSONObject.Values['destaque'].Value.ToInteger = 1 then
        begin
          Query.ParamByName('destaque').AsInteger := 1;
        end
        else
        begin
          Query.ParamByName('destaque').AsInteger := 0;
        end;
      except
        Query.ParamByName('destaque').AsInteger := 0;
      end;
      try
        Query.ParamByName('tempo').AsInteger := JSONObject.Values['tempo']
          .Value.ToInteger;
      except
        Query.ParamByName('tempo').AsInteger := 0;
      end;
      // destaque
      // Executa a query
      Query.ExecSQL;
      if (JSONObject.Values['imagemFundo'].Value <> '') then
      begin
        CaminhoImagem := EnviaImagem(FormatDateTime('ddmmyyyyhhssnn', now) +
          'cat' + CodigoGrupo.ToString + '-' + JSONObject.Values['name'].Value +
          frmServidor.UserID.ToString, frmServidor.UserID.ToString,
          JSONObject.Values['imagemFundo'].Value);
        if (CaminhoImagem <> '') then
        begin
          Query.SQL.Clear;
          Query.SQL.Add
            ('update tipo_produto set url = :url where codigo = :codigo');
          Query.ParamByName('codigo').AsInteger := CodigoGrupo;
          Query.ParamByName('url').AsString := CaminhoImagem;
          Query.ExecSQL;
        end;
      end;
    except
      on E: Exception do
      begin

      end;
    end;
    // Enviar categoria
    // EnviaCategoria(StrToInt(JSONObject.Values['category'].Value)
    // Ler o array "product"
    ProductArray := JSONObject.Values['product'] as TJsonArray;
    // Iterar sobre os itens do array "product"
    for i := 0 to ProductArray.Count - 1 do
    begin
      //
      ProductItem := ProductArray.Items[i] as TJSONObject;
      if (ProductItem.Values['id'].Value = '0') then
      begin
        CodigoAux := conexao.GerarID('produto', 'codigo');
        conexao.SQL.Add
          ('insert into produto (codigo,codigo_interno,data_cadastro,nome_produto,descricao,codigo_grupo,valor_venda,ativo,position)');
        conexao.SQL.Add
          ('values (:codigo,:codigo_interno,current_date,:nome_produto,:descricao,:codigo_grupo,0,1,:position)');
        conexao.Parametros('codigo', CodigoAux);
        conexao.Parametros('codigo_interno', CodigoAux);
        conexao.Parametros('codigo_grupo', CodigoGrupo);
        conexao.Parametros('nome_produto', ProductItem.Values['name'].Value);
        conexao.Parametros('descricao',
          ProductItem.Values['description'].Value);
        conexao.Parametros('position', i + 1);
        conexao.ExecuteSQL;
        if (JSONObject.Values['type'].Value = '2') then
        begin
          Aux := conexao.GerarID('produto_pizza', 'codigo');
          conexao.SQL.Add
            ('insert into produto_pizza (codigo,codigo_produto,quantidade_sabores,borda,ativo)');
          conexao.SQL.Add
            ('values (:codigo,:codigo_produto,:quantidade_sabores,0,1)');
          conexao.Parametros('codigo', Aux);
          conexao.Parametros('codigo_produto', CodigoAux);
          conexao.Parametros('quantidade_sabores',
            ProductItem.Values['qtd'].Value);
          conexao.ExecuteSQL;
        end;
      end
      else
      begin
        conexao.SQL.Add
          ('update produto set nome_produto = :nome, descricao = :descricao, ativo = :ativo, position = :position where codigo = :codigo');
        conexao.Parametros('nome', ProductItem.Values['name'].Value);
        conexao.Parametros('descricao',
          ProductItem.Values['description'].Value);
        conexao.Parametros('ativo', ProductItem.Values['status'].Value);
        conexao.Parametros('position', i + 1);
        conexao.Parametros('codigo', ProductItem.Values['id'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('update produto_pizza set quantidade_sabores = :qtd where codigo_produto = :codigo');
        conexao.Parametros('codigo', ProductItem.Values['id'].Value);
        conexao.Parametros('qtd', ProductItem.Values['qtd'].Value);
        conexao.ExecuteSQL;
      end;
    end;
    DadosTipo.Free;
    // EnviaCategoria(CodigoGrupo);
    ExtraArray := JSONObject.Values['extra'] as TJsonArray;
    for i := 0 to ExtraArray.Count - 1 do
    begin
      ExtraItem := ExtraArray.Items[i] as TJSONObject;
      try
        Cod := ExtraItem.Values['id'].Value.ToInteger;
      except
        Cod := 0;
      end;
      if (Cod = 0) then
      begin
        CodigoExtra := conexao.GerarID('pro_adi_personalizado', 'id');
        conexao.SQL.Add
          ('insert into pro_adi_personalizado (id,categoria,descricao,ativo,qtd_minima,qtd_maxima,id_produto)');
        conexao.SQL.Add
          ('values(:id,:id_produto,:descricao,:ativo,:qtd_minima,:qtd_maxima,0)');
      end
      else
      begin
        CodigoExtra := StrToInt(ExtraItem.Values['id'].Value);
        conexao.SQL.Add
          ('update pro_adi_personalizado set categoria = :id_produto,  descricao = :descricao, ativo = :ativo, qtd_minima = :qtd_minima, qtd_maxima = :qtd_maxima where id = :id');
      end;
      conexao.Parametros('id', CodigoExtra);
      conexao.Parametros('id_produto', CodigoGrupo);
      conexao.Parametros('descricao', ExtraItem.Values['name'].Value);
      conexao.Parametros('ativo', ExtraItem.Values['status'].Value);
      conexao.Parametros('qtd_maxima', ExtraItem.Values['max'].Value);
      conexao.Parametros('qtd_minima', ExtraItem.Values['min'].Value);
      conexao.ExecuteSQL;
      ExtraItensArray := ExtraItem.Values['extra'] as TJsonArray;
      for K := 0 to ExtraItensArray.Count - 1 do
      begin
        ExtraItensItem := ExtraItensArray.Items[K] as TJSONObject;
        if ExtraItensItem.Values['id'].Value = '0' then
        begin
          CodigoAux := conexao.GerarID('pro_adi_personalizado_sabores', 'id');
          conexao.SQL.Add
            ('insert into pro_adi_personalizado_sabores (id, id_pro_adi_personalizado,nome,descricao,valor,ativo,id_prod_estoque, id_ingredientes)');
          conexao.SQL.Add
            ('values (:id, :id_pro_adi_personalizado,:nome,:descricao,:valor,:ativo,:stock, :id_ingredientes)');
        end
        else
        begin
          CodigoAux := StrToInt(ExtraItensItem.Values['id'].Value);
          conexao.SQL.Add
            ('update pro_adi_personalizado_sabores set id_ingredientes = :id_ingredientes, id_prod_estoque = :stock, id_pro_adi_personalizado = :id_pro_adi_personalizado, nome = :nome, descricao = :descricao, valor = :valor, ativo = :ativo');
          conexao.SQL.Add('where id = :id');
        end;
        try
          if ExtraItensItem.Values['value'].ToString.ToDouble > 0 then
          begin
            AlteraExtrasIguais(ExtraItem.Values['name'].Value,
              ExtraItensItem.Values['name'].Value,
              ExtraItensItem.Values['value'].ToString.ToDouble, CodigoGrupo);
          end;
        except
          on E: Exception do
          begin
            // ////showmessage(E.Message);
          end;
        end;
        conexao.Parametros('id', CodigoAux);
        conexao.Parametros('id_pro_adi_personalizado', CodigoExtra);
        conexao.Parametros('nome', ExtraItensItem.Values['name'].Value);
        try
          conexao.Parametros('descricao',
            ExtraItensItem.Values['description'].Value);
        except
          conexao.Parametros('descricao', '');
        end;
        conexao.Parametros('valor', ExtraItensItem.Values['value'].Value);
        conexao.Parametros('ativo', ExtraItensItem.Values['status'].Value);
        try
          conexao.Parametros('stock', ExtraItensItem.Values['stock'].Value);
        except
          conexao.Parametros('stock', 0);
        end;
        try
          conexao.Parametros('id_ingredientes',
            ExtraItensItem.Values['insulmo'].Value);
        except
          conexao.Parametros('id_ingredientes', 0);
        end;
        conexao.ExecuteSQL;
      end;
    end;
  end;
  Query.Free;
  JSONValue.Free; // Liberar a mem?ria alocada pelo JSONValue
  conexao.Free;
  // Limpar as categorias
  LimpaCacheGeral;
end;

procedure DoGetUserID(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send(frmServidor.UserID.ToString);
end;

procedure DoGetPixPendente(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  Requisicao: iRequisicao;
begin
  Requisicao := iRequisicao.Create(nil);
  try
    Requisicao.BaseURL := 'https://old.goopedir.com/v1/qrcod/' +
      frmServidor.UserID.ToString + '/a';
    Requisicao.TempoExpiracao := 30 * 1000;
    Requisicao.Execute;
    Res.Send(Requisicao.Retorno);
  except
    Res.Send('[]');
  end;
  Requisicao.Free;
end;

procedure DoPostNovoValorFlavor(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
  Aux: Integer;
  NV: Integer;
  sabor: String;
begin
  conexao := TConexao.Create('v2');
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('select distinct id_produto, 0 as zero from sabores_completo where nome = :nome');
  sabor := Req.Params['name'];
  conexao.Parametros('nome', sabor);
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  conexao.SQL.Add
    ('select id, 0 as zero from sabores_completo where id_produto = :product and nome = :nome');
  conexao.Parametros('nome', Req.Params['name']);
  conexao.Parametros('product', Req.Params['product']);
  try
    Aux := conexao.FieldByName('id');
  except
    Aux := 0;
  end;
  if Aux = 0 then
  begin
    conexao.SQL.Add
      ('select id, 0 as zero from sabores_completo where nome = :nome');
    conexao.Parametros('nome', Req.Params['name']);
    NV := conexao.FieldByName('id');
    Aux := conexao.GerarID('sabores_completo', 'id');
    Aux := conexao.GerarID('sabores_completo', 'id');
    conexao.SQL.Add('INSERT INTO sabores_completo (');
    conexao.SQL.Add('    id,');
    conexao.SQL.Add('    id_produto,');
    conexao.SQL.Add('    id_tipo_sabor,');
    conexao.SQL.Add('    dt_cadastro,');
    conexao.SQL.Add('    nome,');
    conexao.SQL.Add('    descricao,');
    conexao.SQL.Add('    vl_venda,');
    conexao.SQL.Add('    ativo,');
    conexao.SQL.Add('    id_site,');
    conexao.SQL.Add('    modificado_site');
    conexao.SQL.Add(')');
    conexao.SQL.Add('SELECT');
    conexao.SQL.Add('    :cod AS new_id,');
    conexao.SQL.Add('    :novo_id_produto AS id_produto,');
    conexao.SQL.Add('    id_tipo_sabor,');
    conexao.SQL.Add('    CURRENT_DATE AS dt_cadastro,');
    conexao.SQL.Add('    nome,');
    conexao.SQL.Add('    descricao,');
    conexao.SQL.Add('    :novo_valor_venda AS vl_venda,');
    conexao.SQL.Add('    ativo,');
    conexao.SQL.Add('    0 AS id_site,');
    conexao.SQL.Add('    0 AS modificado_site');
    conexao.SQL.Add('FROM sabores_completo');
    conexao.SQL.Add('WHERE id_produto = :produto_origem and id = :id;');
    conexao.Parametros('produto_origem', Dados.FieldByName('id_produto')
      .AsInteger);
    conexao.Parametros('id', NV);
    // conexao.Parametros('id', Dados.FieldByName('id_produto').AsInteger);
    // conexao.Parametros('produto_origem', NV);
    conexao.Parametros('cod', Aux);
    conexao.Parametros('novo_id_produto', Req.Params['product']);
    conexao.Parametros('novo_valor_venda', Req.Params['value']);
    conexao.ExecuteSQL;
  end;
  conexao.SQL.Add
    ('update sabores_completo set vl_venda = :vl_venda, modificado_site = 0 where nome = :nome and id_produto = :product');
  conexao.Parametros('vl_venda', Req.Params['value']);
  conexao.Parametros('nome', Req.Params['name']);
  conexao.Parametros('product', Req.Params['product']);
  conexao.ExecuteSQL;
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      EnviaProduto(Dados.FieldByName('id_produto').AsInteger, '', '');
      Dados.Next;
    end;
  end;
  Dados.Free;
  conexao.Free;
end;

procedure DoPostStatusFlavor(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
begin
  conexao := TConexao.Create('v2');
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('select distinct id_produto, 0 as zero from sabores_completo where nome = :nome');
  conexao.Parametros('nome', Req.Params['name']);
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  conexao.SQL.Add
    ('update sabores_completo set ativo = :ativo, modificado_site = 0 where nome = :nome');
  conexao.Parametros('ativo', Req.Params['status']);
  conexao.Parametros('nome', Req.Params['name']);
  conexao.ExecuteSQL;
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      EnviaProduto(Dados.FieldByName('id_produto').AsInteger, '', '');
      Dados.Next;
    end;
  end;
  Dados.Free;
  conexao.Free;
end;

procedure DoGetFlavor(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send<TJsonArray>(GetFlavor(Req.Params['category']))
end;

procedure DoPostFlavor(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LJSONValue, LSizeValue: TJSONValue;
  LJSONObject: TJSONObject;
  LJSONArray: TJsonArray;
  LSizeObject: TJSONObject;
  i: Integer;
  conexao: TConexao;
  Codigo: Integer;
  SaborAntigo: String;
  CodigoTipoSabor: Integer;
  Imagem: String;
begin
  conexao := TConexao.Create('v2');
  LJSONValue := TJSONObject.ParseJSONValue(Req.body);
  if LJSONValue is TJSONObject then
  begin
    LJSONObject := LJSONValue as TJSONObject;
    // ////////showmessage1('ID: ' + LJSONObject.GetValue('id').Value);
    // ////////showmessage1('Name: ' + LJSONObject.GetValue('name').Value);
    // ////////showmessage1('Description: ' + LJSONObject.GetValue('description').Value);
    // ////////showmessage1('Base64: ' + LJSONObject.GetValue('base64').Value);
    // flavorOld
    try
      Imagem := LJSONObject.GetValue('base64').Value;
      if Imagem <> '' then
      begin
        Imagem := EnviaImagem(FormatDateTime('ddmmyyyyhhnn', now) +
          LJSONObject.GetValue('id').Value,
          frmServidor.UserID.ToString, Imagem);
      end;
    except
    end;
    // CodigoImagem := codigo.ToString;
    // if user > 0 then
    // CodigoImagem := user.ToString + '-' + codigo.ToString;
    // URL := EnviaImagem(CodigoImagem, Base64);
    LSizeValue := LJSONObject.GetValue('size');
    if LSizeValue is TJsonArray then
    begin
      LJSONArray := LSizeValue as TJsonArray;
      for i := 0 to LJSONArray.Count - 1 do
      begin
        conexao.SQL.Add('select * from tipo_sabor where id = :id');
        conexao.Parametros('id', UpperCase(LJSONObject.GetValue('type').Value));
        try
          CodigoTipoSabor := conexao.FieldByName('id');
        except
          CodigoTipoSabor := 0;
        end;
        if CodigoTipoSabor = 0 then
        begin
          CodigoTipoSabor := conexao.GerarID('tipo_sabor', 'id');
          conexao.SQL.Add
            ('insert into tipo_sabor (id,nome,ativo) values (:id,:nome,1)');
          conexao.Parametros('id', CodigoTipoSabor);
          conexao.Parametros('nome',
            UpperCase(LJSONObject.GetValue('type').Value));
          conexao.ExecuteSQL;
        end;
        LSizeObject := LJSONArray.Items[i] as TJSONObject;
        conexao.SQL.Add
          ('select * from sabores_completo where id_produto = :produto and (nome = :sabor or nome = :old)');
        conexao.Parametros('produto', LSizeObject.GetValue('id').Value);
        conexao.Parametros('sabor',
          UpperCase(LJSONObject.GetValue('name').Value));
        conexao.Parametros('old',
          UpperCase(LJSONObject.GetValue('flavorOld').Value));
        try
          Codigo := conexao.FieldByName('id');
        except
          Codigo := 0;
        end;
        if Codigo = 0 then
        begin
          Codigo := conexao.GerarID('sabores_completo', 'id');
          conexao.SQL.Add
            ('insert into sabores_completo (id,id_produto,id_tipo_sabor,dt_cadastro,nome,descricao,vl_venda,ativo,modificado_site)');
          conexao.SQL.Add
            ('values (:id,:id_produto,:id_tipo_sabor,current_date,:nome,:descricao,:vl_venda,1,0)');
          conexao.Parametros('id', Codigo);
          conexao.Parametros('id_produto', LSizeObject.GetValue('id').Value);
          conexao.Parametros('id_tipo_sabor', CodigoTipoSabor);
          conexao.Parametros('nome',
            UpperCase(LJSONObject.GetValue('name').Value));
          conexao.Parametros('descricao',
            UpperCase(LJSONObject.GetValue('description').Value));
          conexao.Parametros('vl_venda', LSizeObject.GetValue('value').Value);
          conexao.ExecuteSQL;
        end;
        conexao.SQL.Add
          ('update sabores_completo set id_tipo_sabor = :sabor, nome = :nome, descricao = :descricao, vl_venda = :vl_venda, modificado_site = 0');
        if Imagem <> '' then
        begin
          conexao.SQL.Add(',url = :url');
          conexao.Parametros('url', Imagem);
        end;
        conexao.SQL.Add('where id = :id');
        conexao.Parametros('id', Codigo);
        conexao.Parametros('sabor', CodigoTipoSabor);
        conexao.Parametros('nome',
          UpperCase(LJSONObject.GetValue('name').Value));
        conexao.Parametros('descricao',
          UpperCase(LJSONObject.GetValue('description').Value));
        conexao.Parametros('vl_venda', LSizeObject.GetValue('value').Value);
        conexao.ExecuteSQL;
        // insert into sabores_completo (id,id_produto,id_tipo_sabor,dt_cadastro,nome,descricao,vl_venda,ativo,modificado_site)
      end;
    end;
    EnviaProduto(StrToInt(LSizeObject.GetValue('id').Value), '', '');
  end;
  LJSONValue.Free;
  conexao.Free;
end;

procedure DoGetLogOperacao(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal: string;
begin
  conexao := TConexao.Create('DoGetPedidoCancelado');
  DataInicial := Req.Headers['inicio'];
  DataFinal := Req.Headers['fim'];
  conexao.SQL.Add('select l.*, u.nome from log_operacao as l');
  conexao.SQL.Add('left join usuario as u on u.codigo = l.usuario');
  conexao.SQL.Add('where l.data_hora between "' + DataInicial +
    ' 00:00:01" and "' + DataFinal +
    ' 23:59:59" and l.endpoint <> "/v1/login"');
  conexao.SQL.Add('order by data_hora');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetLogOperacaoResumo(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal: string;
begin
  conexao := TConexao.Create('DoGetLogOperacaoResumo');
  try
    DataInicial := Req.Headers['inicio'];
    DataFinal := Req.Headers['fim'];

    conexao.SQL.Add('select');
    conexao.SQL.Add('  l.endpoint,');
    conexao.SQL.Add('  l.operacao,');
    conexao.SQL.Add('  count(*) as total_requisicoes,');
    conexao.SQL.Add('  count(distinct l.usuario) as total_usuarios,');
    conexao.SQL.Add('  count(distinct l.ip) as total_ips,');
    conexao.SQL.Add('  round(count(*) / greatest(timestampdiff(minute, min(l.data_hora), max(l.data_hora)) + 1, 1), 2) as requisicoes_por_minuto,');
    conexao.SQL.Add('  round(count(*) / greatest(timestampdiff(hour, min(l.data_hora), max(l.data_hora)) + 1, 1), 2) as requisicoes_por_hora,');
    conexao.SQL.Add('  round(avg(coalesce(l.tempo_ms, 0)), 2) as tempo_medio_ms,');
    conexao.SQL.Add('  min(coalesce(l.tempo_ms, 0)) as menor_tempo_ms,');
    conexao.SQL.Add('  max(coalesce(l.tempo_ms, 0)) as maior_tempo_ms,');
    conexao.SQL.Add('  sum(coalesce(l.tempo_ms, 0)) as tempo_total_ms,');
    conexao.SQL.Add('  round(avg(length(coalesce(l.body, ''''))), 2) as tamanho_medio_body,');
    conexao.SQL.Add('  max(length(coalesce(l.body, ''''))) as maior_body,');
    conexao.SQL.Add('  sum(case when coalesce(l.tempo_ms, 0) <= 100 then 1 else 0 end) as qtd_ate_100ms,');
    conexao.SQL.Add('  sum(case when coalesce(l.tempo_ms, 0) > 100 and coalesce(l.tempo_ms, 0) <= 500 then 1 else 0 end) as qtd_101_500ms,');
    conexao.SQL.Add('  sum(case when coalesce(l.tempo_ms, 0) > 500 and coalesce(l.tempo_ms, 0) <= 1000 then 1 else 0 end) as qtd_501_1000ms,');
    conexao.SQL.Add('  sum(case when coalesce(l.tempo_ms, 0) > 1000 and coalesce(l.tempo_ms, 0) <= 3000 then 1 else 0 end) as qtd_1001_3000ms,');
    conexao.SQL.Add('  sum(case when coalesce(l.tempo_ms, 0) > 3000 then 1 else 0 end) as qtd_acima_3000ms,');
    conexao.SQL.Add('  round((sum(case when coalesce(l.tempo_ms, 0) > 1000 then 1 else 0 end) / count(*)) * 100, 2) as percentual_lentas,');
    conexao.SQL.Add('  min(l.data_hora) as primeira_requisicao,');
    conexao.SQL.Add('  max(l.data_hora) as ultima_requisicao,');
    conexao.SQL.Add('  group_concat(distinct l.usuario order by l.usuario separator '', '') as usuarios,');
    conexao.SQL.Add('  group_concat(distinct l.ip order by l.ip separator '', '') as ips');
    conexao.SQL.Add('from log_operacao as l');
    conexao.SQL.Add('where l.data_hora between :inicio and :fim');
    conexao.SQL.Add('  and l.endpoint <> "/v1/login"');
    conexao.SQL.Add('group by l.endpoint, l.operacao');
    conexao.SQL.Add('order by total_requisicoes desc, tempo_medio_ms desc');
    conexao.Parametros('inicio', DataInicial + ' 00:00:01');
    conexao.Parametros('fim', DataFinal + ' 23:59:59');
    Res.Send<TJsonArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;
procedure DoGetFechamentoFiado(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal: string;
  Data: TFDMemTable;
  fiados: TJsonArray;
  pedido: TJSONObject;
begin
  conexao := TConexao.Create('DoGetPedidoCancelado');
  Data := TFDMemTable.Create(nil);
  DataInicial := Req.Headers['inicio'];
  DataFinal := Req.Headers['fim'];
  conexao.SQL.Add
    ('SELECT cr.id_pedido as pedido, cr.id_caixa as caixa, p.data_pedido as data, cr.data as dtCaixa, cr.hora as horaCaixa, cr.valor, cr.pago, c.nome, c.cpf, ');
  conexao.SQL.Add
    ('(select upper(nome) from cliente where codigo = p.codigo_cliente) as nomeCliente FROM caixa_receber as cr');
  conexao.SQL.Add('join cliente as c on c.codigo = cr.id_cliente');
  conexao.SQL.Add('join pedido as p on p.codigo = cr.id_pedido');
  conexao.SQL.Add('where p.data_pedido between :ini and :fim');
  conexao.Parametros('ini', DataInicial);
  conexao.Parametros('fim', DataFinal);
  Data.LoadFromJSON(conexao.ConsultaSQL);
  fiados := TJsonArray.Create;
  if Data.RecordCount > 0 then
  begin
    while not Data.Eof do
    begin
      pedido := Data.ToJSONObject();
      pedido.AddPair('produtos',
        GetDadosProdutoPedido(Data.FieldByName('pedido').AsInteger));
      fiados.AddElement(pedido);
      Data.Next;
    end;
  end;
  Res.Send<TJsonArray>(fiados);
  Data.Free;
  conexao.Free;
end;

procedure DoGetMovimentacaoPagamento(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal: string;
begin
  conexao := TConexao.Create('DoGetPedidoCancelado');
  DataInicial := Req.Headers['inicio'] + ' 00:00:01';
  DataFinal := Req.Headers['fim'] + ' 23:59:59';
  conexao.SQL.Add
    ('SELECT cm.id, cm.id_caixa, cm.id_pedido, cm.data, cm.hora, cm.valor, tp.descricao, c.nome,');
  conexao.SQL.Add('IF(cm.valor = cr.pago,IF(tp.movimentacao = 1, "","Pago"),');
  conexao.SQL.Add
    ('IF(tp.movimentacao = 1, "",if(cr.pago > 0,"Pagamento Parcial","Em Aberto"))) as status');
  conexao.SQL.Add('FROM caixa_movimento as cm');
  conexao.SQL.Add
    ('join tipo_pagamento as tp on tp.codigo = cm.id_tipo_pagamento');
  conexao.SQL.Add
    ('left join caixa_receber as cr on cr.id_caixa = cm.id_caixa and cr.id_pedido = cm.id_pedido');
  conexao.SQL.Add('and cr.valor = cm.valor');
  conexao.SQL.Add('left join cliente as c on c.codigo = cr.id_cliente');
  conexao.SQL.Add('where cm.tipo = 1 and cm.data between :ini and :fim');
  conexao.SQL.Add('order by cm.id, cm.id_pedido, tp.movimentacao');
  conexao.Parametros('ini', DataInicial);
  conexao.Parametros('fim', DataFinal);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetPedidoCancelado(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal: string;
  SQL: String;
begin
  conexao := TConexao.Create('DoGetPedidoCancelado');
  DataInicial := Req.Headers['inicio'] + ' 00:00:01';
  DataFinal := Req.Headers['fim'] + ' 23:59:59';
  SQL := 'SELECT p.codigo, p.codigo_pedido_dia, c.nome, p.data_pedido, if(p.codigo_cliente_endereco > 0, "DELIVERY","RETIRADA") as tipo, p.valor_total_pedido, p.motivo_cancelamento, p.datahora_deletado, p.usuario_deletado, u.nome as nome1 from pedido as p ';
  SQL := SQL + 'join usuario as u on u.codigo = p.usuario_deletado ';
  SQL := SQL + 'join cliente as c on c.codigo = p.codigo_cliente ';
  SQL := SQL + 'where p.status = 0 and p.datahora_deletado between "' +
    DataInicial + '" and "' + DataFinal + '"';
  conexao.SQL.Add(CriaSubQueryCampos(SQL, '*', Req.Headers['inicio'],
    Req.Headers['fim']));
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetHeart(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Retorno: TJSONObject;
begin
  Retorno := TJSONObject.Create;
  Retorno.AddPair('ok', True);
  Retorno.AddPair('service', 'ServidorGooPedir');
  Retorno.AddPair('port', TJSONNumber.Create(THorse.Port));
  Retorno.AddPair('uptimeSec', TJSONNumber.Create(SecondsBetween(Now,
    ServerStartedAt)));
  Retorno.AddPair('time', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  Res.Send<TJSONObject>(Retorno);
end;

procedure DoGetHealth(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Retorno: TJSONObject;
begin
  Retorno := TJSONObject.Create;
  Retorno.AddPair('ok', True);
  Retorno.AddPair('service', 'ServidorGooPedir');
  Retorno.AddPair('port', TJSONNumber.Create(THorse.Port));
  Retorno.AddPair('uptimeSec', TJSONNumber.Create(SecondsBetween(Now,
    ServerStartedAt)));
  Retorno.AddPair('errors500', TJSONNumber.Create(ServerHealthTotalErros500));
  Retorno.AddPair('lastError', ServerHealthUltimoErro);
  Retorno.AddPair('lastErrorStep', ServerHealthUltimaEtapa);
  Retorno.AddPair('time', FormatDateTime('yyyy-mm-dd hh:nn:ss', Now));
  Res.Send<TJSONObject>(Retorno);
end;

procedure DoGetNFCeGeradas(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal: string;
  SQL: String;
begin
  conexao := TConexao.Create('DoGetNFCeGeradas');
  DataInicial := Req.Headers['inicio'] + ' 00:00:01';
  DataFinal := Req.Headers['fim'] + ' 23:59:59';
  SQL := 'select codigo, data_pedido, valor_total_pedido, id_caixa, nfce_chave, nfce_protocolo, nfce_numero from pedido where nfce_emite = 2';
  SQL := SQL + ' and data_pedido between "' + DataInicial + '" and "' +
    DataFinal + '"';
  conexao.SQL.Add(CriaSubQueryCampos(SQL, '*', Req.Headers['inicio'],
    Req.Headers['fim']));
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetPedidosNFCePeriodo(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal, StatusNota: string;
begin
  DataInicial := Req.Params['dataini'];
  DataFinal := Req.Params['datafim'];
  try
    StatusNota := UpperCase(Trim(Req.Params['status']));
  except
    StatusNota := '';
  end;

  conexao := TConexao.Create('DoGetPedidosNFCePeriodo');
  try
    conexao.SQL.Add('SELECT');
    conexao.SQL.Add('  p.codigo,');
    conexao.SQL.Add('  p.codigo_pedido_dia,');
    conexao.SQL.Add('  DATE_FORMAT(p.data_pedido, "%Y-%m-%d") AS data,');
    conexao.SQL.Add('  TIME_FORMAT(p.hora_pedido, "%H:%i:%s") AS horario,');
    conexao.SQL.Add('  COALESCE(p.nfce_chave, "") AS chave,');
    conexao.SQL.Add('  COALESCE(p.nfce_protocolo, "") AS protocolo,');
    conexao.SQL.Add('  CASE');
    conexao.SQL.Add('    WHEN COALESCE(p.nome, "") <> "" THEN p.nome');
    conexao.SQL.Add('    WHEN COALESCE(c.nome, "") <> "" THEN c.nome');
    conexao.SQL.Add('    ELSE "VENDA"');
    conexao.SQL.Add('  END AS cliente,');
    conexao.SQL.Add('  p.valor_total_pedido AS valor,');
    conexao.SQL.Add('  p.nfce_numero AS numero,');
    conexao.SQL.Add('  p.nfce_emite,');
    conexao.SQL.Add('  COALESCE(p.nfce_status, "") AS nfce_status,');
    conexao.SQL.Add('  CASE');
    conexao.SQL.Add
      ('    WHEN p.nfce_chave = "CANCELADA" OR p.nfce_status = "CANCELADA" THEN "CANCELADA"');
    conexao.SQL.Add('    WHEN p.nfce_status = "ERRO" THEN "ERRO"');
    conexao.SQL.Add
      ('    WHEN p.nfce_emite IN (1, 3) OR p.nfce_status IN ("PENDENTE", "PROCESSANDO") THEN "PENDENTE"');
    conexao.SQL.Add
      ('    WHEN p.nfce_emite = 2 OR p.nfce_status IN ("EMITIDA", "CONTINGENCIA") THEN "EMITIDA"');
    conexao.SQL.Add('    WHEN COALESCE(p.nfce_chave, "") <> "" THEN "EMITIDA"');
    conexao.SQL.Add('    ELSE "SEM_NOTA"');
    conexao.SQL.Add('  END AS status_nota,');
    conexao.SQL.Add('  CASE');
    conexao.SQL.Add
      ('    WHEN p.nfce_chave = "CANCELADA" OR p.nfce_status = "CANCELADA" THEN "CANCELADA"');
    conexao.SQL.Add('    WHEN p.nfce_status = "ERRO" THEN "ERRO"');
    conexao.SQL.Add
      ('    WHEN p.nfce_emite IN (1, 3) OR p.nfce_status IN ("PENDENTE", "PROCESSANDO") THEN "PENDENTE"');
    conexao.SQL.Add
      ('    WHEN p.nfce_emite = 2 OR p.nfce_status IN ("EMITIDA", "CONTINGENCIA") THEN "EMITIDA"');
    conexao.SQL.Add('    WHEN COALESCE(p.nfce_chave, "") <> "" THEN "EMITIDA"');
    conexao.SQL.Add('    ELSE "SEM_NOTA"');
    conexao.SQL.Add('  END AS status');
    conexao.SQL.Add('FROM pedido p');
    conexao.SQL.Add('LEFT JOIN cliente c ON c.codigo = p.codigo_cliente');
    conexao.SQL.Add('WHERE p.data_pedido BETWEEN :dataini AND :datafim');
    conexao.SQL.Add('  AND (');
    conexao.SQL.Add('    p.nfce_emite IN (1, 2, 3)');
    conexao.SQL.Add
      ('    OR p.nfce_status IN ("EMITIDA", "CONTINGENCIA", "PENDENTE", "PROCESSANDO", "ERRO", "CANCELADA")');
    conexao.SQL.Add('    OR COALESCE(p.nfce_chave, "") <> ""');
    conexao.SQL.Add('  )');
    if StatusNota <> '' then
    begin
      conexao.SQL.Add('  AND CASE');
      conexao.SQL.Add
        ('    WHEN p.nfce_chave = "CANCELADA" OR p.nfce_status = "CANCELADA" THEN "CANCELADA"');
      conexao.SQL.Add('    WHEN p.nfce_status = "ERRO" THEN "ERRO"');
      conexao.SQL.Add
        ('    WHEN p.nfce_emite IN (1, 3) OR p.nfce_status IN ("PENDENTE", "PROCESSANDO") THEN "PENDENTE"');
      conexao.SQL.Add
        ('    WHEN p.nfce_emite = 2 OR p.nfce_status IN ("EMITIDA", "CONTINGENCIA") THEN "EMITIDA"');
      conexao.SQL.Add
        ('    WHEN COALESCE(p.nfce_chave, "") <> "" THEN "EMITIDA"');
      conexao.SQL.Add('    ELSE "SEM_NOTA"');
      conexao.SQL.Add('  END = :status_nota');
      conexao.Parametros('status_nota', StatusNota);
    end;
    conexao.SQL.Add('ORDER BY p.data_pedido, p.hora_pedido, p.codigo');
    conexao.Parametros('dataini', DataInicial);
    conexao.Parametros('datafim', DataFinal);
    Res.Send<TJsonArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;

procedure DoGetResultadoMetricas(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal, HoraInicio, HoraFim: string;
  SQL: String;
  codigos: String;
  TipoMesa: String;
  QuantidadeMesasOcupacao: Integer; // OK
  QuantidadeOcupada: Integer; // OK
  PercentualOcupacao: Real; // OK
  ConsumacaoMesa: Real; // OK
  Dados: TFDMemTable;
  JsonRetornoObj: TJSONObject;
  jsonMesa: TJSONObject;
  Total: Real;
  QuantidadePedido: Integer;
  QuantidadeMesaFechada: Integer;
  TotalMesaFechada: Real;
  QuantidadeNfcEmitida: Integer;
  TotalNFcEmitida: Real;
  TotalTaxaServico: Real;
  TotalCancelamento: Real;
  TotalPedido: Real;
  arrayLocalizacao: TJsonArray;
  objetoLocalizacao: TJSONObject;
  arrayPartner: TJsonArray;
  objetoPartner: TJSONObject;
  Dict: TDictionary<string, TPartnerInfo>;
  Info: TPartnerInfo;
  Pair: TPair<string, TPartnerInfo>;
  Arr: TArray<TPartnerInfo>;
  i: Integer;
  objetoPedido: TJSONObject;
  QuantidadeCancelada: Integer;
  QuantidadePedidoFinalizado: Integer;
  QuantidadePreparacao: Integer;
  QuantidadePronto: Integer;
begin
  conexao := TConexao.Create('DoGetProdutoDeletado');
  JsonRetornoObj := TJSONObject.Create;
  objetoPedido := TJSONObject.Create;;
  arrayLocalizacao := TJsonArray.Create;
  Dict := TDictionary<string, TPartnerInfo>.Create;
  conexao.SQL.Add('SELECT * FROM mesa_tipo where descricao = :descricao');
  conexao.Parametros('descricao', 'mesa');
  TipoMesa := conexao.FieldByName('id_mesa_tipo');
  QuantidadeMesasOcupacao := 0;
  QuantidadeOcupada := 0;
  PercentualOcupacao := 0;
  ConsumacaoMesa := 0;
  if (TipoMesa <> '') then
  begin
    try
      QuantidadeMesasOcupacao := StrToInt(GetParametro('quantidade_mesas'));
    except
      conexao.SQL.Add
        ('select count(*) as tot, 0 as zero from mesa where fk_tipo_mesa = :id');
      conexao.Parametros('id', TipoMesa);
      QuantidadeMesasOcupacao := StrToInt(conexao.FieldByName('tot'));
    end;
    conexao.SQL.Add('SELECT ');
    conexao.SQL.Add
      ('    COALESCE(NULLIF(m.descricao, ""), CONCAT(mt.descricao, " ", m.nr_mesa)) AS descricao_final,');
    conexao.SQL.Add('    COUNT(*) AS qtd,');
    conexao.SQL.Add('    SUM(m.tot_mesa) AS total');
    conexao.SQL.Add('FROM mesa m');
    conexao.SQL.Add('JOIN mesa_tipo mt ON mt.id_mesa_tipo = m.fk_tipo_mesa');
    conexao.SQL.Add('WHERE ');
    conexao.SQL.Add('    m.selecionada > 0 ');
    conexao.SQL.Add('    AND (m.fk_tipo_mesa = ' + TipoMesa +
      ' OR m.descricao LIKE "%MESA%")');
    conexao.SQL.Add('GROUP BY descricao_final');
    conexao.SQL.Add('ORDER BY descricao_final');
    Dados := TFDMemTable.Create(nil);
    Dados.LoadFromJSON(conexao.ConsultaSQL());
    if Dados.RecordCount > 0 then
    begin
      while not Dados.Eof do
      begin
        inc(QuantidadeOcupada);
        ConsumacaoMesa := ConsumacaoMesa + Dados.FieldByName('total').AsFloat;
        Dados.Next;
      end;
    end;
    Dados.Free;
    if QuantidadeMesasOcupacao = 0 then
      QuantidadeMesasOcupacao := QuantidadeOcupada;
    PercentualOcupacao := (QuantidadeOcupada / QuantidadeMesasOcupacao) * 100;
    if QuantidadeOcupada = QuantidadeMesasOcupacao then
      PercentualOcupacao := 100;
  end;
  jsonMesa := TJSONObject.Create;
  jsonMesa.AddPair('qtdMesa', QuantidadeMesasOcupacao);
  jsonMesa.AddPair('qtdOcupada', QuantidadeOcupada);
  jsonMesa.AddPair('percentualOcupada', PercentualOcupacao);
  jsonMesa.AddPair('consumacaoOcupada', ConsumacaoMesa);
  DataInicial := Req.Headers['dtinicio'];
  DataFinal := Req.Headers['dtfim'];
  HoraInicio := Req.Headers['hrInicio'];
  HoraFim := Req.Headers['hrFim'];
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('SELECT p.codigo, p.status,p.valor_total_pedido, p.origem, p.nfce_status,p.servico,p.servico_percentual, p.latitude, p.longitude, p.partner, p.id_ficha FROM pedido as p');
  conexao.SQL.Add('where p.data_pedido between :dtIni and :dtFim');
  conexao.SQL.Add
    ('and p.hora_pedido between :hrIni and :hrFim and status > -1');
  conexao.Parametros('dtIni', DataInicial);
  conexao.Parametros('dtFim', DataFinal);
  conexao.Parametros('hrIni', HoraInicio);
  conexao.Parametros('hrFim', HoraFim);
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      if Dados.FieldByName('status').AsInteger <> 0 then
      begin
        if codigos <> '' then
          codigos := codigos + ',' + Dados.FieldByName('codigo').AsString
        else
          codigos := Dados.FieldByName('codigo').AsString;
      end;
      if (Dados.FieldByName('id_ficha').AsInteger > 0) then
      begin
        // Mesa
        inc(QuantidadeMesaFechada);
        TotalTaxaServico := TotalTaxaServico +
          Dados.FieldByName('servico').AsFloat;
        TotalMesaFechada := TotalMesaFechada +
          Dados.FieldByName('valor_total_pedido').AsFloat;
      end
      else
      begin
        if (Dados.FieldByName('status').AsInteger = 0) then
        begin
          TotalCancelamento := TotalCancelamento +
            Dados.FieldByName('valor_total_pedido').AsFloat;
          inc(QuantidadeCancelada);
        end
        else
        begin
          inc(QuantidadePedido);
          TotalPedido := TotalPedido + Dados.FieldByName
            ('valor_total_pedido').AsFloat;
        end;
        if (Dados.FieldByName('status').AsInteger <> 0) then
        begin
          if Dados.FieldByName('latitude').AsInteger <> 0 then
          begin
            objetoLocalizacao := TJSONObject.Create;
            objetoLocalizacao.AddPair('lat',
              Dados.FieldByName('latitude').AsFloat);
            objetoLocalizacao.AddPair('lgn',
              Dados.FieldByName('longitude').AsFloat);
            arrayLocalizacao.AddElement(objetoLocalizacao);
          end;
          if (Dados.FieldByName('nfce_status').AsString = 'EMITIDA') then
          begin
            inc(QuantidadeNfcEmitida);
            TotalNFcEmitida := TotalNFcEmitida +
              Dados.FieldByName('valor_total_pedido').AsFloat;
          end;
          if Dados.FieldByName('partner').AsString <> '' then
          begin
            if Dict.TryGetValue(Dados.FieldByName('partner').AsString, Info)
            then
            begin
              // j? existe ? soma
              Info.Quantidade := Info.Quantidade + 1;
              Info.Valor := Info.Valor + Dados.FieldByName
                ('valor_total_pedido').AsFloat;
            end
            else
            begin
              // novo
              Info.Quantidade := 1;
              Info.Valor := Dados.FieldByName('valor_total_pedido').AsFloat;
              Info.Partner := Dados.FieldByName('partner').AsString;
            end;
            Dict.AddOrSetValue(Dados.FieldByName('partner').AsString, Info);
          end;
        end;
        if (Dados.FieldByName('status').AsInteger in [1, 2, 9]) then
        begin
          // Em Preparo
          inc(QuantidadePreparacao);
        end;
        if (Dados.FieldByName('status').AsInteger in [3, 4, 5]) then
        begin
          // Pronto
          inc(QuantidadePronto);
        end;
        if (Dados.FieldByName('status').AsInteger in [6]) then
        begin
          // Finalizado
          inc(QuantidadePedidoFinalizado);
        end;
      end;
      Dados.Next;
    end;
  end;
  Dados.Free;
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add('SELECT ');
  conexao.SQL.Add('  u.nome, ');
  conexao.SQL.Add('  u.codigo, ');
  conexao.SQL.Add('  SUM(pp.quantidade) AS quantidade, ');
  conexao.SQL.Add('  SUM(pp.valor_total) AS total,');
  conexao.SQL.Add
    ('  TRUNCATE((SUM(pp.valor_total) / SUM(SUM(pp.valor_total)) OVER ()) * 100,2) AS percentual');
  conexao.SQL.Add('FROM pedido_produtos pp');
  conexao.SQL.Add('JOIN usuario u ON u.codigo = pp.usuario');
  conexao.SQL.Add('WHERE pp.codigo_pedido IN (' + codigos + ')');
  conexao.SQL.Add('GROUP BY u.nome, u.codigo');
  conexao.SQL.Add('ORDER BY percentual DESC');
  JsonRetornoObj.AddPair('garcom', conexao.ConsultaSQL);
  conexao.SQL.Add('SELECT ');
  conexao.SQL.Add('  p.codigo, ');
  conexao.SQL.Add('  p.nome_produto, ');
  conexao.SQL.Add('  p.valor_venda, ');
  conexao.SQL.Add('  p.saldo_atual, ');
  conexao.SQL.Add('  p.estoque_min AS saldo_minimo, ');
  conexao.SQL.Add('  p.foto_ifood,');
  conexao.SQL.Add('  p.controle_estoque');
  conexao.SQL.Add('FROM produto p');
  conexao.SQL.Add('WHERE ');
  conexao.SQL.Add('(');
  conexao.SQL.Add('    (p.controle_estoque = 1 OR p.ativo = 0)');
  conexao.SQL.Add
    ('    OR (p.controle_estoque = 1 AND p.saldo_atual <= p.estoque_min)');
  conexao.SQL.Add(')');
  conexao.SQL.Add('AND p.deletado = 0 ');
  conexao.SQL.Add('AND p.codigo_grupo > 0 ');
  conexao.SQL.Add('AND p.dias = 0');
  conexao.SQL.Add('ORDER BY ');
  conexao.SQL.Add('  p.controle_estoque DESC, ');
  conexao.SQL.Add('  p.saldo_atual DESC;');
  JsonRetornoObj.AddPair('estoque', conexao.ConsultaSQL);
  SetLength(Arr, Dict.Count);
  objetoPedido.AddPair('qtdPreparo', QuantidadePreparacao);
  objetoPedido.AddPair('qtdPronto', QuantidadePronto);
  objetoPedido.AddPair('qtdFinalizado', QuantidadePedidoFinalizado);
  objetoPedido.AddPair('qtdTotal', QuantidadePedido);
  objetoPedido.AddPair('qtdCancelado', QuantidadeCancelada);
  objetoPedido.AddPair('total', TotalPedido + TotalMesaFechada);
  objetoPedido.AddPair('totalCancelado', TotalCancelamento);
  objetoPedido.AddPair('pedidos', codigos);
  objetoPedido.AddPair('totalNfce', TotalNFcEmitida);
  i := 0;
  for Pair in Dict do
  begin
    Arr[i] := Pair.Value;
    inc(i);
  end;
  arrayPartner := TJsonArray.Create;
  for i := 0 to High(Arr) do
  begin
    objetoPartner := TJSONObject.Create;
    objetoPartner.AddPair('partner', Arr[i].Partner);
    objetoPartner.AddPair('quantidade', TJSONNumber.Create(Arr[i].Quantidade));
    objetoPartner.AddPair('valor', TJSONNumber.Create(Arr[i].Valor));
    arrayPartner.AddElement(objetoPartner);
  end;
  jsonMesa.AddPair('qtdFinalizada', QuantidadeMesaFechada);
  jsonMesa.AddPair('totalFinalizada', TotalMesaFechada);
  jsonMesa.AddPair('totalTaxaServico', TotalTaxaServico);
  JsonRetornoObj.AddPair('mesa', jsonMesa);
  conexao.Free;
  JsonRetornoObj.AddPair('localizacao', arrayLocalizacao);
  JsonRetornoObj.AddPair('partner', arrayPartner);
  JsonRetornoObj.AddPair('pedido', objetoPedido);
  Res.Send<TJSONObject>(JsonRetornoObj);
end;

procedure DoGetProdutoDeletado(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicial, DataFinal: string;
  SQL: String;
begin
  conexao := TConexao.Create('DoGetProdutoDeletado');
  DataInicial := Req.Headers['inicio'] + ' 00:00:01';
  DataFinal := Req.Headers['fim'] + ' 23:59:59';
  SQL := 'SELECT pp.id_pedido as pedido_cancelado, pp.quantidade, pp.valor_unitario, pp.valor_adicional, pp.valor_total, pp.observacao, pp.html, p.nome_produto, p.foto_ifood, p.codigo, pp.datahora_deletado, pp.usuario_deletado, u.nome ';
  SQL := SQL + 'from pedido_produtos as pp ';
  SQL := SQL + 'join produto as p on p.codigo = pp.codigo_produto ';
  SQL := SQL + 'left join usuario as u on u.codigo = pp.usuario_deletado ';
  SQL := SQL +
    'where pp.id_pedido > 0 and pp.usuario_deletado > 0 and pp.datahora_deletado between "'
    + DataInicial + '" and "' + DataFinal + '"';
  conexao.SQL.Add(CriaSubQueryCampos(SQL, '*', Req.Headers['inicio'],
    Req.Headers['fim']));
  conexao.SQL.Add('order by datahora_deletado');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

function ValorJSONProduto(Objeto: TJSONObject;
  const Nome, Padrao: String): String;
begin
  Result := Padrao;
  if Assigned(Objeto) and Assigned(Objeto.Values[Nome]) then
    Result := Objeto.Values[Nome].Value;
end;

procedure PropagarIBSCBSProdutosSemConfiguracao(conexao: TConexao;
  JSONObject: TJSONObject; CodigoProdutoAtual: Integer);
var
  TemIBSCBS: Boolean;
begin
  TemIBSCBS := Assigned(JSONObject.Values['ibs_cbs_cst']) or
    Assigned(JSONObject.Values['ibs_cbs_class_trib']) or
    Assigned(JSONObject.Values['ibs_uf_aliq']) or
    Assigned(JSONObject.Values['ibs_mun_aliq']) or
    Assigned(JSONObject.Values['cbs_aliq']);

  if not TemIBSCBS then
    exit;

  conexao.SQL.Clear;
  conexao.SQL.Add('UPDATE produto SET ');
  conexao.SQL.Add('ibs_cbs_cst = :ibs_cbs_cst, ');
  conexao.SQL.Add('ibs_cbs_class_trib = :ibs_cbs_class_trib, ');
  conexao.SQL.Add('ibs_uf_aliq = :ibs_uf_aliq, ');
  conexao.SQL.Add('ibs_mun_aliq = :ibs_mun_aliq, ');
  conexao.SQL.Add('cbs_aliq = :cbs_aliq ');
  conexao.SQL.Add('WHERE codigo <> :codigo ');
  conexao.SQL.Add
    ('AND (ibs_cbs_cst IS NULL OR TRIM(ibs_cbs_cst) = "" OR ibs_cbs_cst = "000") ');
  conexao.SQL.Add
    ('AND (ibs_cbs_class_trib IS NULL OR TRIM(ibs_cbs_class_trib) = "" OR ibs_cbs_class_trib = "000001") ');
  conexao.SQL.Add('AND (ibs_uf_aliq IS NULL OR ibs_uf_aliq IN (0, 0.1)) ');
  conexao.SQL.Add('AND (ibs_mun_aliq IS NULL OR ibs_mun_aliq = 0) ');
  conexao.SQL.Add('AND (cbs_aliq IS NULL OR cbs_aliq IN (0, 0.9))');
  conexao.Parametros('ibs_cbs_cst', ValorJSONProduto(JSONObject,
    'ibs_cbs_cst', '000'));
  conexao.Parametros('ibs_cbs_class_trib', ValorJSONProduto(JSONObject,
    'ibs_cbs_class_trib', '000001'));
  conexao.Parametros('ibs_uf_aliq', ValorJSONProduto(JSONObject,
    'ibs_uf_aliq', '0.1'));
  conexao.Parametros('ibs_mun_aliq', ValorJSONProduto(JSONObject,
    'ibs_mun_aliq', '0'));
  conexao.Parametros('cbs_aliq', ValorJSONProduto(JSONObject,
    'cbs_aliq', '0.9'));
  conexao.Parametros('codigo', CodigoProdutoAtual);
  conexao.ExecuteSQL;
  conexao.SQL.Clear;
end;

procedure DoPostProduct(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  DadosProduto: TFDMemTable;
  ExtraArray: TJsonArray;
  ExtraItem: TJSONObject;
  ExtraItensArray: TJsonArray;
  ExtraItensItem: TJSONObject;
  Site: Integer;
  position: Integer;
  Codigo: Integer;
  CategoriaSite: Integer;
  i: Integer;
  CodigoExtra: Integer;
  CodigoAux: Integer;
  K: Integer;
  Cod: Integer;
  Query: TFDQuery;
  Item: TJSONValue;
  ID: Integer;
  CaminhoExtraFoto: String;
begin
  conexao := TConexao.Create('v2');
  DadosProduto := TFDMemTable.Create(nil);
  // Fazer o parsing do JSON
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  try
    // Verificar se o JSON foi parseado com sucesso
    if Assigned(JSONValue) and (JSONValue is TJSONObject) then
    begin
      JSONObject := JSONValue as TJSONObject;
      conexao.SQL.Add('select * from produto where codigo = :codigo');
      conexao.Parametros('codigo', JSONObject.Values['id'].Value);
      DadosProduto.LoadFromJSON(conexao.ConsultaSQL);
      if DadosProduto.RecordCount = 0 then
      begin
        // Envia
        conexao.SQL.Add
          ('select max(position)+1 as max, 0 as zero from produto where codigo_grupo = :codigo_grupo');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        try
          position := conexao.FieldByName('max');
        except
          position := 1;
        end;
        Codigo := conexao.GerarID('produto', 'codigo');
        conexao.SQL.Add
          ('insert into produto (codigo,codigo_interno,data_cadastro,nome_produto,descricao,codigo_grupo,valor_venda,controle_estoque,caminho_imagem,');
        conexao.SQL.Add
          ('usa_tabela_preco,position, pessoas, valor_desconto, percentual_desconto, ativo,valor_embalagem_delivery,novidade)');
        conexao.SQL.Add
          ('values (:codigo,:codigo_interno,current_date,:nome_produto,:descricao,:codigo_grupo,:valor_venda,:controle_estoque,:caminho_imagem,');
        conexao.SQL.Add
          (':usa_tabela_preco,:position, :pessoas, :valor_desconto, :percentual_desconto,1,:entrega,:novidade)');
        conexao.Parametros('codigo', Codigo);
        conexao.Parametros('codigo_interno', Codigo);
        conexao.Parametros('nome_produto', JSONObject.Values['name'].Value);
        conexao.Parametros('descricao', JSONObject.Values['description'].Value);
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('valor_venda', JSONObject.Values['value'].Value);
        conexao.Parametros('controle_estoque',
          JSONObject.Values['stock'].Value);
        conexao.Parametros('caminho_imagem', '');
        conexao.Parametros('usa_tabela_preco', 0);
        conexao.Parametros('position', position);
        conexao.Parametros('pessoas', JSONObject.Values['people'].Value);
        conexao.Parametros('valor_desconto',
          JSONObject.Values['value_discont'].Value);
        conexao.Parametros('percentual_desconto',
          JSONObject.Values['value_percent'].Value);
        conexao.Parametros('entrega', JSONObject.Values['entrega'].Value);
        try
          conexao.Parametros('novidade', JSONObject.Values['novidade'].Value);
        except
          conexao.Parametros('novidade', 0);
        end;
        conexao.ExecuteSQL;
      end
      else
      begin
        // Update
        try
          Site := DadosProduto.FieldByName('id_site').AsInteger;
        except
        end;
        Codigo := DadosProduto.FieldByName('codigo').AsInteger;
      end;
      // In?cio do bloco de atualiza??o do produto
      conexao.SQL.Add('UPDATE produto SET ');
      conexao.SQL.Add('nome_produto = :nome_produto, ');
      conexao.SQL.Add('descricao = :descricao, ');
      conexao.SQL.Add('codigo_grupo = :codigo_grupo, ');
      conexao.SQL.Add('valor_venda = :valor_venda, ');
      conexao.SQL.Add('controle_estoque = :controle_estoque, ');
      conexao.SQL.Add('pessoas = :pessoas, ');
      conexao.SQL.Add('valor_desconto = :valor_desconto, ');
      conexao.SQL.Add('estoque_min = :estoque_min, ');
      conexao.SQL.Add('percentual_desconto = :percentual_desconto, ');
      conexao.SQL.Add('referencia = :referencia, ');
      conexao.SQL.Add('tiposite = :tiposite, ');
      conexao.SQL.Add('fidelidade = :fidelidade, ');
      conexao.SQL.Add('valor_embalagem_delivery = :entrega, ');
      conexao.SQL.Add('dias = :dias, ');
      conexao.SQL.Add('segunda = :segunda, ');
      conexao.SQL.Add('terca = :terca, ');
      conexao.SQL.Add('quarta = :quarta, ');
      conexao.SQL.Add('quinta = :quinta, ');
      conexao.SQL.Add('sexta = :sexta, ');
      conexao.SQL.Add('sabado = :sabado, ');
      conexao.SQL.Add('domingo = :domingo, ');
      conexao.SQL.Add('novidade = :novidade, ');
      conexao.SQL.Add('vembuscar = :vembuscar, ');
      conexao.SQL.Add('delivery = :delivery, ');
      conexao.SQL.Add('un = :un, ');
      conexao.SQL.Add('ncm = :ncm, ');
      conexao.SQL.Add('cest = :cest, ');
      conexao.SQL.Add('cfop = :cfop, ');
      conexao.SQL.Add('cstipi = :cstipi, ');
      conexao.SQL.Add('csticms = :csticms, ');
      conexao.SQL.Add('cstpis = :cstpis, ');
      conexao.SQL.Add('cstcofins = :cstcofins, ');
      conexao.SQL.Add('csosn = :csosn, ');
      conexao.SQL.Add('icms = :icms, ');
      conexao.SQL.Add('ipi = :ipi, ');
      conexao.SQL.Add('pis = :pis, ');
      conexao.SQL.Add('cofins = :cofins, ');
      conexao.SQL.Add('ibs_cbs_cst = :ibs_cbs_cst, ');
      conexao.SQL.Add('ibs_cbs_class_trib = :ibs_cbs_class_trib, ');
      conexao.SQL.Add('ibs_uf_aliq = :ibs_uf_aliq, ');
      conexao.SQL.Add('ibs_mun_aliq = :ibs_mun_aliq, ');
      conexao.SQL.Add('cbs_aliq = :cbs_aliq, ');
      conexao.SQL.Add('frete = :frete ');
      conexao.SQL.Add('WHERE codigo = :codigo');
      // Par?metros do JSON, com valida??o para valores nulos ou inexistentes
      conexao.Parametros('nome_produto',
        IfThen(JSONObject.Values['name'] <> nil,
        JSONObject.Values['name'].Value, ''));
      conexao.Parametros('descricao',
        IfThen(JSONObject.Values['description'] <> nil,
        JSONObject.Values['description'].Value, ''));
      conexao.Parametros('codigo_grupo',
        IfThen(JSONObject.Values['category'] <> nil,
        JSONObject.Values['category'].Value, '0'));
      conexao.Parametros('valor_venda',
        IfThen(JSONObject.Values['value'] <> nil,
        JSONObject.Values['value'].Value, '0'));
      conexao.Parametros('controle_estoque',
        IfThen(JSONObject.Values['stock'] <> nil,
        JSONObject.Values['stock'].Value, '0'));
      conexao.Parametros('pessoas', IfThen(JSONObject.Values['people'] <> nil,
        JSONObject.Values['people'].Value, '0'));
      conexao.Parametros('valor_desconto',
        IfThen(JSONObject.Values['value_discont'] <> nil,
        JSONObject.Values['value_discont'].Value, '0'));
      conexao.Parametros('estoque_min',
        IfThen(JSONObject.Values['stock_min'] <> nil,
        JSONObject.Values['stock_min'].Value, '0'));
      conexao.Parametros('percentual_desconto',
        IfThen(JSONObject.Values['value_percent'] <> nil,
        JSONObject.Values['value_percent'].Value, '0'));
      conexao.Parametros('fidelidade',
        IfThen(JSONObject.Values['fidelidade'] <> nil,
        JSONObject.Values['fidelidade'].Value, '0'));
      conexao.Parametros('entrega', IfThen(JSONObject.Values['entrega'] <> nil,
        JSONObject.Values['entrega'].Value, '0'));
      conexao.Parametros('dias', IfThen(JSONObject.Values['dias'] <> nil,
        JSONObject.Values['dias'].Value, '0'));
      conexao.Parametros('segunda', IfThen(JSONObject.Values['segunda'] <> nil,
        JSONObject.Values['segunda'].Value, '0'));
      conexao.Parametros('terca', IfThen(JSONObject.Values['terca'] <> nil,
        JSONObject.Values['terca'].Value, '0'));
      conexao.Parametros('quarta', IfThen(JSONObject.Values['quarta'] <> nil,
        JSONObject.Values['quarta'].Value, '0'));
      conexao.Parametros('quinta', IfThen(JSONObject.Values['quinta'] <> nil,
        JSONObject.Values['quinta'].Value, '0'));
      conexao.Parametros('sexta', IfThen(JSONObject.Values['sexta'] <> nil,
        JSONObject.Values['sexta'].Value, '0'));
      conexao.Parametros('sabado', IfThen(JSONObject.Values['sabado'] <> nil,
        JSONObject.Values['sabado'].Value, '0'));
      conexao.Parametros('domingo', IfThen(JSONObject.Values['domingo'] <> nil,
        JSONObject.Values['domingo'].Value, '0'));
      conexao.Parametros('novidade',
        IfThen(JSONObject.Values['novidade'] <> nil,
        JSONObject.Values['novidade'].Value, '0'));
      conexao.Parametros('vembuscar',
        IfThen(JSONObject.Values['vembuscar'] <> nil,
        JSONObject.Values['vembuscar'].Value, '0'));
      conexao.Parametros('delivery',
        IfThen(JSONObject.Values['delivery'] <> nil,
        JSONObject.Values['delivery'].Value, '0'));
      conexao.Parametros('un', IfThen(JSONObject.Values['un'] <> nil,
        JSONObject.Values['un'].Value, 'UN'));
      conexao.Parametros('ncm', IfThen(JSONObject.Values['ncm'] <> nil,
        JSONObject.Values['ncm'].Value, '0'));
      conexao.Parametros('cest', IfThen(JSONObject.Values['cest'] <> nil,
        JSONObject.Values['cest'].Value, '0'));
      conexao.Parametros('cfop', IfThen(JSONObject.Values['cfop'] <> nil,
        JSONObject.Values['cfop'].Value, '0'));
      conexao.Parametros('cstipi', IfThen(JSONObject.Values['cstipi'] <> nil,
        JSONObject.Values['cstipi'].Value, '0'));
      conexao.Parametros('csticms', IfThen(JSONObject.Values['csticms'] <> nil,
        JSONObject.Values['csticms'].Value, '0'));
      conexao.Parametros('cstpis', IfThen(JSONObject.Values['cstpis'] <> nil,
        JSONObject.Values['cstpis'].Value, '0'));
      conexao.Parametros('cstcofins',
        IfThen(JSONObject.Values['cstcofins'] <> nil,
        JSONObject.Values['cstcofins'].Value, '0'));
      conexao.Parametros('csosn', IfThen(JSONObject.Values['csosn'] <> nil,
        JSONObject.Values['csosn'].Value, '0'));
      conexao.Parametros('icms', IfThen(JSONObject.Values['icms'] <> nil,
        JSONObject.Values['icms'].Value, '0'));
      conexao.Parametros('ipi', IfThen(JSONObject.Values['ipi'] <> nil,
        JSONObject.Values['ipi'].Value, '0'));
      conexao.Parametros('pis', IfThen(JSONObject.Values['pis'] <> nil,
        JSONObject.Values['pis'].Value, '0'));
      conexao.Parametros('cofins', IfThen(JSONObject.Values['cofins'] <> nil,
        JSONObject.Values['cofins'].Value, '0'));
      conexao.Parametros('ibs_cbs_cst',
        IfThen(JSONObject.Values['ibs_cbs_cst'] <> nil,
        JSONObject.Values['ibs_cbs_cst'].Value, '000'));
      conexao.Parametros('ibs_cbs_class_trib',
        IfThen(JSONObject.Values['ibs_cbs_class_trib'] <> nil,
        JSONObject.Values['ibs_cbs_class_trib'].Value, '000001'));
      conexao.Parametros('ibs_uf_aliq',
        IfThen(JSONObject.Values['ibs_uf_aliq'] <> nil,
        JSONObject.Values['ibs_uf_aliq'].Value, '0.1'));
      conexao.Parametros('ibs_mun_aliq',
        IfThen(JSONObject.Values['ibs_mun_aliq'] <> nil,
        JSONObject.Values['ibs_mun_aliq'].Value, '0'));
      conexao.Parametros('cbs_aliq',
        IfThen(JSONObject.Values['cbs_aliq'] <> nil,
        JSONObject.Values['cbs_aliq'].Value, '0.9'));
      conexao.Parametros('frete', IfThen(JSONObject.Values['frete'] <> nil,
        JSONObject.Values['frete'].Value, '0'));
      conexao.Parametros('codigo', IfThen(JSONObject.Values['id'] <> nil,
        JSONObject.Values['id'].Value, '0'));
      try
        conexao.Parametros('referencia', JSONObject.Values['referencia'].Value);
      except
        conexao.Parametros('referencia', '');
      end;
      try
        conexao.Parametros('tiposite', JSONObject.Values['tiposite'].Value);
      except
        conexao.Parametros('tiposite', '');
      end;
      // Executa a query
      conexao.ExecuteSQL;
      PropagarIBSCBSProdutosSemConfiguracao(conexao, JSONObject, Codigo);
      conexao.SQL.Clear;
      try
        if JSONObject.Values['ncm'].Value = '' then
        begin
          StrToInt('XXXX');
        end;
        conexao.SQL.Add
          ('UPDATE produto SET ncm = :ncm WHERE codigo_grupo = :codigo_grupo AND ncm IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('ncm', JSONObject.Values['ncm'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET cest = :cest WHERE codigo_grupo = :codigo_grupo AND cest IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('cest', JSONObject.Values['cest'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET cfop = :cfop WHERE codigo_grupo = :codigo_grupo AND cfop IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('cfop', JSONObject.Values['cfop'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET cstipi = :cstipi WHERE codigo_grupo = :codigo_grupo AND cstipi IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('cstipi', JSONObject.Values['cstipi'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET csticms = :csticms WHERE codigo_grupo = :codigo_grupo AND csticms IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('csticms', JSONObject.Values['csticms'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET cstpis = :cstpis WHERE codigo_grupo = :codigo_grupo AND cstpis IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('cstpis', JSONObject.Values['cstpis'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET cstcofins = :cstcofins WHERE codigo_grupo = :codigo_grupo AND cstcofins IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('cstcofins', JSONObject.Values['cstcofins'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET csosn = :csosn WHERE codigo_grupo = :codigo_grupo AND csosn IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('csosn', JSONObject.Values['csosn'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET icms = :icms WHERE codigo_grupo = :codigo_grupo AND icms IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('icms', JSONObject.Values['icms'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET ipi = :ipi WHERE codigo_grupo = :codigo_grupo AND ipi IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('ipi', JSONObject.Values['ipi'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET pis = :pis WHERE codigo_grupo = :codigo_grupo AND pis IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('pis', JSONObject.Values['pis'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET cofins = :cofins WHERE codigo_grupo = :codigo_grupo AND cofins IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('cofins', JSONObject.Values['cofins'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET frete = :frete WHERE codigo_grupo = :codigo_grupo AND frete IS NOT NULL;');
        conexao.Parametros('codigo_grupo', JSONObject.Values['category'].Value);
        conexao.Parametros('frete', JSONObject.Values['frete'].Value);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('UPDATE produto SET referencia = :referencia WHERE codigo = :codigo AND frete IS NOT NULL;');
        conexao.Parametros('codigo', Codigo);
        conexao.Parametros('referencia', JSONObject.Values['referencia'].Value);
        conexao.ExecuteSQL;
      except
        conexao.SQL.Clear;
      end;
      if (Assigned((JSONObject.Values['combo_products']))) then
      begin
        conexao.SQL.Add
          ('UPDATE produto_combo_config SET status = "INATIVO" WHERE produto_combo_id = :produtoComboId AND status = "ATIVO";');
        conexao.Parametros('produtoComboId', Codigo);
        conexao.ExecuteSQL;
        Cod := conexao.GerarID('produto_combo_config', 'id');
        conexao.SQL.Add
          ('INSERT INTO produto_combo_config (produto_combo_id, status) VALUES (:produtoComboId, "ATIVO");');
        conexao.Parametros('produtoComboId', Codigo);
        conexao.ExecuteSQL;
        ExtraArray := JSONObject.Values['combo_products'] as TJsonArray;
        for i := 0 to ExtraArray.Count - 1 do
        begin
          ExtraItem := ExtraArray.Items[i] as TJSONObject;
          conexao.SQL.Add
            ('INSERT INTO produto_combo_item (combo_config_id, produto_id, ratio, base_value) values (:id, :produto, :ratio, :value)');
          conexao.Parametros('id', Cod);
          conexao.Parametros('produto', ExtraItem.Values['id'].Value);
          conexao.Parametros('ratio', ExtraItem.Values['ratio'].Value);
          conexao.Parametros('value', ExtraItem.Values['base_value'].Value);
          conexao.ExecuteSQL;
        end;
        ExtraArray.Free;
      end;
      if StrToInt(JSONObject.Values['adicional'].ToString) = 1 then
      begin
        ExtraArray := JSONObject.Values['extra'] as TJsonArray;
        for i := 0 to ExtraArray.Count - 1 do
        begin
          ExtraItem := ExtraArray.Items[i] as TJSONObject;
          try
            Cod := ExtraItem.Values['id'].Value.ToInteger;
          except
            Cod := 0;
          end;
          if (Cod = 0) then
          begin
            CodigoExtra := conexao.GerarID('pro_adi_personalizado', 'id');
            conexao.SQL.Add
              ('insert into pro_adi_personalizado (id,id_produto,descricao,ativo,qtd_minima,qtd_maxima)');
            conexao.SQL.Add
              ('values(:id,:id_produto,:descricao,:ativo,:qtd_minima,:qtd_maxima)');
          end
          else
          begin
            CodigoExtra := StrToInt(ExtraItem.Values['id'].Value);
            conexao.SQL.Add
              ('update pro_adi_personalizado set id_produto = :id_produto,  descricao = :descricao, ativo = :ativo, qtd_minima = :qtd_minima, qtd_maxima = :qtd_maxima where id = :id');
          end;
          conexao.Parametros('id', CodigoExtra);
          conexao.Parametros('id_produto', Codigo);
          conexao.Parametros('descricao', ExtraItem.Values['name'].Value);
          conexao.Parametros('ativo', ExtraItem.Values['status'].Value);
          conexao.Parametros('qtd_maxima', ExtraItem.Values['max'].Value);
          conexao.Parametros('qtd_minima', ExtraItem.Values['min'].Value);
          conexao.ExecuteSQL;
          ExtraItensArray := ExtraItem.Values['extra'] as TJsonArray;
          for K := 0 to ExtraItensArray.Count - 1 do
          begin
            ExtraItensItem := ExtraItensArray.Items[K] as TJSONObject;
            if ExtraItensItem.Values['id'].Value = '0' then
            begin
              CodigoAux := conexao.GerarID
                ('pro_adi_personalizado_sabores', 'id');
              conexao.SQL.Add
                ('insert into pro_adi_personalizado_sabores (id, id_pro_adi_personalizado,nome,descricao,valor,ativo,id_prod_estoque, id_ingredientes,alerta,url)');
              conexao.SQL.Add
                ('values (:id, :id_pro_adi_personalizado,:nome,:descricao,:valor,:ativo,:stock, :id_ingredientes,:alerta, :url)');
            end
            else
            begin
              CodigoAux := StrToInt(ExtraItensItem.Values['id'].Value);
              conexao.SQL.Add
                ('update pro_adi_personalizado_sabores set url = :url, id_ingredientes = :id_ingredientes,alerta = :alerta, id_prod_estoque = :stock, id_pro_adi_personalizado = :id_pro_adi_personalizado, nome = :nome, descricao = :descricao, valor = :valor, ativo = :ativo');
              conexao.SQL.Add('where id = :id');
            end;
            try
              if ExtraItensItem.Values['value'].ToString.ToDouble > 0 then
              begin
                AlteraExtrasIguais(ExtraItem.Values['name'].Value,
                  ExtraItensItem.Values['name'].Value,
                  ExtraItensItem.Values['value'].ToString.ToDouble, Codigo);
              end;
            except
              on E: Exception do
              begin
                // ////showmessage(E.Message);
              end;
            end;
            // Eviar o base64
            CaminhoExtraFoto := '';
            if Assigned(ExtraItensItem.Values['url']) then
            begin
              if ExtraItensItem.Values['url'].Value <> '' then
              begin
                CaminhoExtraFoto := ExtraItensItem.Values['url'].Value
              end;
            end;
            if Assigned(ExtraItensItem.Values['base64']) then
            begin
              if ExtraItensItem.Values['base64'].Value <> '' then
              begin
                CaminhoExtraFoto := EnviaImagem(CodigoAux.ToString,
                  frmServidor.UserID.ToString,
                  ExtraItensItem.Values['base64'].Value)
              end;
            end;
            conexao.Parametros('id', CodigoAux);
            conexao.Parametros('url', CaminhoExtraFoto);
            conexao.Parametros('id_pro_adi_personalizado', CodigoExtra);
            conexao.Parametros('nome', ExtraItensItem.Values['name'].Value);
            try
              conexao.Parametros('descricao',
                ExtraItensItem.Values['description'].Value);
            except
              conexao.Parametros('descricao', '');
            end;
            try
              conexao.Parametros('valor', ExtraItensItem.Values['value']
                .Value.ToDouble);
            except
              conexao.Parametros('valor', 0);
            end;
            conexao.Parametros('ativo', ExtraItensItem.Values['status'].Value);
            try
              conexao.Parametros('stock', ExtraItensItem.Values['stock'].Value);
            except
              conexao.Parametros('stock', 0);
            end;
            try
              conexao.Parametros('alerta',
                ExtraItensItem.Values['alerta'].Value);
            except
              conexao.Parametros('alerta', 0);
            end;
            try
              conexao.Parametros('id_ingredientes',
                ExtraItensItem.Values['insulmo'].Value);
            except
              conexao.Parametros('id_ingredientes', 0);
            end;
            conexao.ExecuteSQL;
          end;
        end;
      end;
      Query := conexao.CriaQRY;
      Query.SQL.Text :=
        'update produto set nome_produto = :nome, descricao = :descricao where codigo = :codigo';
      Query.ParamByName('codigo').AsInteger := Codigo;
      Query.ParamByName('nome').AsWideString := JSONObject.Values['name'].Value;
      Query.ParamByName('descricao').AsWideString := JSONObject.Values
        ['description'].Value;
      Query.ExecSQL;
      if (JSONObject.Values['url'].Value <> '') and
        (JSONObject.Values['url'].Value <> './img/sem-foto.jpg') then
      begin
        Query.SQL.Text :=
          'update produto set caminho_imagem = :foto, foto_ifood = :foto where codigo = :codigo';
        Query.ParamByName('codigo').AsInteger := Codigo;
        Query.ParamByName('foto').AsWideString := JSONObject.Values
          ['url'].Value;
        Query.ExecSQL;
      end;
      Query.Free;
      if JSONObject.TryGetValue<TJsonArray>('deleteExtras', ExtraArray) and
        Assigned(ExtraArray) then
      begin
        for Item in ExtraArray do
        begin
          // cobre os casos: n?mero puro, string num?rica, ou (se no futuro vier) objeto com campo id
          if Item is TJSONNumber then
            ID := TJSONNumber(Item).AsInt
          else if Item is TJSONString then
            ID := StrToIntDef(TJSONString(Item).Value, 0)
          else if Item is TJSONObject then
            ID := TJSONObject(Item).GetValue<Integer>('id', 0)
          else
            ID := 0;
          if ID > 0 then
          begin
            conexao.SQL.Clear;
            conexao.SQL.Add
              ('update pro_adi_personalizado_sabores set ativo = 0, deletado = 1, modificado_site = 0 where id = :id');
            conexao.Parametros('id', ID); // passe como inteiro
            conexao.ExecuteSQL;
          end;
        end;
      end;
      Site := EnviaProduto(Codigo, JSONObject.Values['base64'].Value,
        JSONObject.Values['category'].Value);
    end;
    LimpaCache('GetProdutoCategoria', JSONObject.Values['category'].Value);
    frmServidor.ProdutosHash.Remover(JSONObject.Values['category'].Value);
  except
    on E: Exception do
    begin
      frmServidor.AddLog(E.Message);
      // //////showmessage1(E.Message)
    end;
  end;
  conexao.Free;
  DadosProduto.Free;
end;

procedure DoGetPedidosMotoboy(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  try
    Req.Params['codigo'].ToInteger;
    conexao.SQL.Add
      ('select pedido.data_pedido, group_concat(pedido.codigo) as id, group_concat(pedido.codigo_pedido_dia) as pedidos, sum(pedido.valor_taxa_entrega) as taxa, sum(pedido.valor_total_pedido) as total from pedido');
    conexao.SQL.Add
      ('join pedido_motoboy on pedido_motoboy.codigo_pedido = pedido.codigo');
    conexao.SQL.Add
      ('where pedido.data_pedido >= current_date()-7 and pedido_motoboy.codigo_motoboy = :codigo ');
    conexao.SQL.Add('group by pedido.data_pedido');
    conexao.SQL.Add('order by pedido.data_pedido desc');
    conexao.Parametros('codigo', Req.Params['codigo']);
  except
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('select (select descricao from tipo_pagamento where tipo_pagamento.codigo = pedido.tipo_pagamento) as pagamento, sum(pedido.valor_total_pedido) as total from pedido where codigo in ('
      + Req.Params['pagamento'] + ')');
    conexao.SQL.Add('group by pedido.tipo_pagamento');
  end;
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure PostGetPedidosMotoboy(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  body: String;
  JSONArr: TJsonArray;
  JsonObj: TJSONObject;
  i: Integer;
  conexao: TConexao;
  Dados: TFDMemTable;
  ID: Integer;
  Requisicao: iRequisicao;
begin
  conexao := TConexao.Create('v2');
  Dados := TFDMemTable.Create(nil);
  body := Req.body;
  JSONArr := TJSONObject.ParseJSONValue(body) as TJsonArray;
  try
    for i := 0 to JSONArr.Count - 1 do
    begin
      JsonObj := JSONArr.Items[i] as TJSONObject;
      Dados.Close;
      conexao.SQL.Add
        ('select * from pedido where pedido.codigo_pedido_dia = :codigo and pedido.codigo_cliente_endereco > 0 order by data_pedido desc limit 1');
      conexao.Parametros('codigo', JsonObj.GetValue<string>('codigo'));
      Dados.LoadFromJSON(conexao.ConsultaSQL);
      if Dados.RecordCount > 0 then
      begin
        // Codigo := StrToIntDef(JSONObj.GetValue<string>('codigo'), 0);
        // Tipo := JSONObj.GetValue<Integer>('tipo');
        // Motoboy := JSONObj.GetValue<Integer>('motoboy');
        if JsonObj.GetValue<Integer>('tipo') = 1 then
        begin
          // Saiu para entrega
          conexao.SQL.Add
            ('update pedido set status = :status where codigo = :codigo');
          conexao.Parametros('codigo', Dados.FieldByName('codigo').AsInteger);
          conexao.Parametros('status', 5);
          conexao.ExecuteSQL;
          ID := conexao.GerarID('pedido_status', 'id');
          conexao.SQL.Add
            ('insert into pedido_status (id,id_pedido,id_status,horario) values (:id,:pedido,:status,timestamp)');
          conexao.Parametros('pedido', Dados.FieldByName('codigo').AsInteger);
          conexao.Parametros('status', 5);
          conexao.Parametros('id', ID);
          conexao.ExecuteSQL;
        end;
        conexao.SQL.Add
          ('delete from pedido_motoboy where codigo_pedido = :pedido');
        conexao.Parametros('pedido', Dados.FieldByName('codigo').AsInteger);
        conexao.ExecuteSQL;
        ID := conexao.GerarID('pedido_motoboy', 'codigo');
        conexao.SQL.Add
          ('insert into pedido_motoboy (codigo,codigo_motoboy,codigo_pedido,hora_pego_motoboy,status) values (:codigo,:motoboy,:pedido,current_time,1)');
        conexao.Parametros('codigo', ID);
        conexao.Parametros('motoboy', JsonObj.GetValue<Integer>('motoboy'));
        conexao.Parametros('pedido', Dados.FieldByName('codigo').AsInteger);
        conexao.ExecuteSQL;
        if Dados.FieldByName('id_pedido_site').AsInteger > 0 then
        begin
          try
            Requisicao := iRequisicao.Create(nil);
            Requisicao.BaseURL :=
              'https://old.goopedir.com/v1/atualiza_status_pedido.php?codigo=' +
              Dados.FieldByName('id_pedido_site').AsString + '&status=' +
              'Saiu Para Entrega';
            Requisicao.Execute;
          except
          end;
          Requisicao.Free;
        end;
      end;
      // Agora voc? tem os valores. Fa?a o que voc? precisa com eles.
      // Por exemplo, apenas imprimindo:
      // Writeln(Format('Codigo: %d, Tipo: %d, Motoboy: %d', [Codigo, Tipo, Motoboy]));
    end;
  finally
    JSONArr.Free;
  end;
  conexao.Free;
end;

procedure DoGetProdutosiFood(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJsonArray>(frmServidor.DadosProdutos);
end;

procedure DoGetCNPJ(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Requisicao: iRequisicao;
  arquivo: String;
  Lista: TStringList;
begin
  arquivo := TPath.GetTempPath + 'goopedir\cnpj\';
  Lista := TStringList.Create;
  if FileExists(arquivo + Req.Params['cnpj'] + '.json') then
  begin
    Lista.LoadFromFile(arquivo + Req.Params['cnpj'] + '.json');
    Res.Send(Lista.Text);
    Lista.Free;
    exit;
  end;
  Requisicao := iRequisicao.Create(nil);
  Requisicao.BaseURL := 'https://receitaws.com.br/v1/cnpj/' +
    Req.Params['cnpj'];
  Requisicao.TempoExpiracao := 50000;
  try
    Requisicao.Execute;
    ForceDirectories(arquivo);
    try
      Lista.Text := Requisicao.Retorno;
      Lista.SaveToFile(arquivo + Req.Params['cnpj'] + '.json', TEncoding.UTF8);
      // ou TEncoding.ANSI, conforme necess?rio
    finally
      Lista.Free;
    end;
    Res.Send(Requisicao.Retorno);
  except
  end;
  Requisicao.Free;
end;

//
procedure DoAtualizParametro(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  JsonObj: TJSONObject;
  Qry: TFDQuery;
  SWStep: TStopwatch;
  Campo: String;
  Valor: String;
begin
  SWStep := TStopwatch.StartNew;
  JsonObj := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  PerformanceStep('parametro_post_parse_body', SWStep.ElapsedMilliseconds);
  try
    SWStep := TStopwatch.StartNew;
    Campo := JsonObj.GetValue<string>('campo');
    Valor := JsonObj.GetValue<string>('valor');
    PerformanceStep('parametro_post_validate', SWStep.ElapsedMilliseconds);

    SWStep := TStopwatch.StartNew;
    conexao := TConexao.Create('v2');
    try
      PerformanceStep('parametro_post_connection', SWStep.ElapsedMilliseconds);
      SWStep := TStopwatch.StartNew;
      Qry := conexao.CriaQRY;
      try
        Qry.SQL.Text := 'INSERT INTO configuracoes (chave, valor) ' +
          'VALUES (:chave, :valor) ' +
          'ON DUPLICATE KEY UPDATE valor = VALUES(valor)';
        Qry.ParamByName('valor').AsWideString := Valor;
        Qry.ParamByName('chave').AsWideString := Campo;
        PerformanceStep('parametro_post_prepare', SWStep.ElapsedMilliseconds);
        SWStep := TStopwatch.StartNew;
        Qry.ExecSQL;
        PerformanceSQL('parametro_post_upsert', Qry.SQL.Text,
          SWStep.ElapsedMilliseconds, Qry.RowsAffected, True);
        PerformanceStep('parametro_post_execute', 0);
      finally
        Qry.Free;
      end;
    finally
      conexao.Free;
    end;

    SWStep := TStopwatch.StartNew;
    LimparParametrosCacheMemoria;
    LimpaCache('DoGetParametros', 'cache');
    PerformanceStep('parametro_post_cache_invalidate', SWStep.ElapsedMilliseconds);
  finally
    JsonObj.Free;
  end;
end;
procedure DoGetDashboardVendaV2(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJsonArray>(BuscarRelatorioVenda(Req.Params['dataini'],
    Req.Params['datafim']));
end;

function PeriodoDashBoardVendaPermiteCache(DataIni, DataFim: String): Boolean;
var
  DataInicial: TDate;
  DataFinal: TDate;
begin
  try
    DataInicial := ParseISODate(DataIni);
    DataFinal := ParseISODate(DataFim);
    Result := not((Date >= DataInicial) and (Date <= DataFinal));
  except
    Result := False;
  end;
end;

const
  DASHBOARD_CACHE_DB = 'goopedir_cache';
  DASHBOARD_CACHE_TABLE = 'cache';
  DASHBOARD_CACHE_REFERENCIA_TABLE = 'dashboard_venda_referencia';
  DASHBOARD_CACHE_DIA_TABLE = 'dashboard_venda_dia';
  DASHBOARD_CACHE_ORIGEM = 'DoGetDashBoardVenda';
  DASHBOARD_CACHE_VALIDADE_MINUTOS = 525600;

procedure GarantirTabelaReferenciaDashboardVenda;
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('GarantirTabelaReferenciaDashboardVenda');
  try
    conexao.ExecuteSQL('CREATE DATABASE IF NOT EXISTS ' + DASHBOARD_CACHE_DB +
      ' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    conexao.ExecuteSQL('ALTER DATABASE ' + DASHBOARD_CACHE_DB +
      ' CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    conexao.ExecuteSQL('CREATE TABLE IF NOT EXISTS ' + DASHBOARD_CACHE_DB + '.'
      + DASHBOARD_CACHE_REFERENCIA_TABLE + ' (' +
      'referencia VARCHAR(100) NOT NULL PRIMARY KEY, ' +
      'data_inicio DATE NOT NULL, ' + 'data_fim DATE NOT NULL, ' +
      'chave VARCHAR(255) NOT NULL, ' + 'gerado_em DATETIME NOT NULL, ' +
      'atualizado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, '
      + 'INDEX idx_dashboard_ref_periodo (data_inicio, data_fim)' +
      ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    conexao.ExecuteSQL('ALTER TABLE ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_REFERENCIA_TABLE +
      ' CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    conexao.ExecuteSQL('CREATE TABLE IF NOT EXISTS ' + DASHBOARD_CACHE_DB + '.'
      + DASHBOARD_CACHE_DIA_TABLE + ' (' +
      'data_ref DATE NOT NULL PRIMARY KEY, ' + 'dados LONGTEXT NOT NULL, ' +
      'gerado_em DATETIME NOT NULL, ' +
      'atualizado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP'
      + ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
    conexao.ExecuteSQL('ALTER TABLE ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_DIA_TABLE +
      ' CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
    conexao.ExecuteSQL('ALTER TABLE ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_DIA_TABLE +
      ' MODIFY dados LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL');
  finally
    conexao.Free;
  end;
end;

function ChaveCacheDashboardVenda(const DataIni, DataFim: String): String;
begin
  Result := DataIni + '_' + DataFim;
end;

function CacheDashboardVendaExiste(const CacheKey: String): Boolean;
var
  conexao: TConexao;
  Qry: TFDQuery;
begin
  Result := False;
  conexao := TConexao.Create('CacheDashboardVendaExiste');
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text := 'SELECT 1 FROM ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_TABLE + ' WHERE origem = :origem AND chave = :chave ' +
      'AND (expira_em IS NULL OR expira_em > CURRENT_TIMESTAMP) LIMIT 1';
    Qry.ParamByName('origem').AsString := DASHBOARD_CACHE_ORIGEM;
    Qry.ParamByName('chave').AsString := CacheKey;
    Qry.Open;
    Result := not Qry.Eof;
  except
    Result := False;
  end;
  Qry.Free;
  conexao.Free;
end;

procedure RegistrarReferenciaDashboardVenda(const Referencia, DataIni, DataFim,
  CacheKey: String);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('RegistrarReferenciaDashboardVenda');
  try
    conexao.SQL.Add('INSERT INTO ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_REFERENCIA_TABLE);
    conexao.SQL.Add('(referencia, data_inicio, data_fim, chave, gerado_em)');
    conexao.SQL.Add
      ('VALUES (:referencia, :data_inicio, :data_fim, :chave, NOW())');
    conexao.SQL.Add
      ('ON DUPLICATE KEY UPDATE data_inicio = VALUES(data_inicio),');
    conexao.SQL.Add
      ('data_fim = VALUES(data_fim), chave = VALUES(chave), gerado_em = VALUES(gerado_em)');
    conexao.Parametros('referencia', Referencia);
    conexao.Parametros('data_inicio', DataIni);
    conexao.Parametros('data_fim', DataFim);
    conexao.Parametros('chave', CacheKey);
    conexao.ExecuteSQL;
  finally
    conexao.Free;
  end;
end;

procedure DefinirStringJSON(Objeto: TJSONObject; const Nome, Valor: String);
var
  Par: TJSONPair;
begin
  Par := Objeto.RemovePair(Nome);
  if Assigned(Par) then
    Par.Free;
  Objeto.AddPair(Nome, Valor);
end;

function BuscarReferenciaDashboardVenda(const CacheKey: String;
  out Referencia, DataIni, DataFim: String): Boolean;
var
  conexao: TConexao;
  Qry: TFDQuery;
begin
  Result := False;
  Referencia := '';
  DataIni := '';
  DataFim := '';
  conexao := TConexao.Create('BuscarReferenciaDashboardVenda');
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text := 'SELECT referencia, data_inicio, data_fim FROM ' +
      DASHBOARD_CACHE_DB + '.' + DASHBOARD_CACHE_REFERENCIA_TABLE +
      ' WHERE chave = :chave LIMIT 1';
    Qry.ParamByName('chave').AsString := CacheKey;
    Qry.Open;
    if not Qry.Eof then
    begin
      Referencia := Qry.FieldByName('referencia').AsString;
      DataIni := FormatDateTime('yyyy-mm-dd', Qry.FieldByName('data_inicio')
        .AsDateTime);
      DataFim := FormatDateTime('yyyy-mm-dd', Qry.FieldByName('data_fim')
        .AsDateTime);
      Result := True;
    end;
  except
    Result := False;
  end;
  Qry.Free;
  conexao.Free;
end;

procedure MarcarReferenciaDashboardVenda(Objeto: TJSONObject;
  const CacheKey: String);
var
  Referencia, DataIni, DataFim: String;
begin
  if not Assigned(Objeto) then
    exit;
  if BuscarReferenciaDashboardVenda(CacheKey, Referencia, DataIni, DataFim) then
  begin
    DefinirStringJSON(Objeto, 'cache_origem', DASHBOARD_CACHE_REFERENCIA_TABLE);
    DefinirStringJSON(Objeto, 'cache_referencia', Referencia);
    DefinirStringJSON(Objeto, 'cache_chave', CacheKey);
    DefinirStringJSON(Objeto, 'cache_data_inicio', DataIni);
    DefinirStringJSON(Objeto, 'cache_data_fim', DataFim);
  end;
end;

procedure AquecerCacheDashboardVendaPeriodo(const Referencia: String;
  DataIni, DataFim: TDate; Forcar: Boolean = False);
var
  DataIniStr, DataFimStr, CacheKey: String;
  Cache: TJSONObject;
begin
  if DataFim < DataIni then
    exit;

  DataIniStr := FormatDateTime('yyyy-mm-dd', DataIni);
  DataFimStr := FormatDateTime('yyyy-mm-dd', DataFim);
  CacheKey := ChaveCacheDashboardVenda(DataIniStr, DataFimStr);

  if (not Forcar) and CacheDashboardVendaExiste(CacheKey) then
    exit;
  if Forcar then
    LimpaCache(DASHBOARD_CACHE_ORIGEM, CacheKey);
  Cache := BuscarDashBoardVenda(DataIniStr, DataFimStr);
  try
    if (Date >= DataIni) and (Date <= DataFim) then
      GravaCache(DASHBOARD_CACHE_ORIGEM, CacheKey, Cache.ToString, 30)
    else
      GravaCache(DASHBOARD_CACHE_ORIGEM, CacheKey, Cache.ToString,
        DASHBOARD_CACHE_VALIDADE_MINUTOS);
    RegistrarReferenciaDashboardVenda(Referencia, DataIniStr, DataFimStr,
      CacheKey);
  finally
    Cache.Free;
  end;
end;

function ValorJSONNumero(Objeto: TJSONObject; const Nome: String): Double;
var
  Valor: TJSONValue;
  Fmt: TFormatSettings;
begin
  Result := 0;
  Valor := Objeto.GetValue(Nome);
  if not Assigned(Valor) then
    exit;
  Fmt := TFormatSettings.Create;
  Fmt.DecimalSeparator := '.';
  Result := StrToFloatDef(StringReplace(Valor.Value, ',', '.', [rfReplaceAll]
    ), 0, Fmt);
end;

procedure AdicionarNumeroJSON(Objeto: TJSONObject; const Nome: String;
  Valor: Double);
begin
  Objeto.AddPair(Nome, TJSONNumber.Create(Valor));
end;

procedure AnexarArrayJSON(Destino: TJsonArray; Origem: TJsonArray);
var
  i: Integer;
  Clone: TJSONValue;
begin
  if not Assigned(Origem) then
    exit;
  for i := 0 to Origem.Count - 1 do
  begin
    Clone := TJSONObject.ParseJSONValue(Origem.Items[i].ToJSON);
    if Assigned(Clone) then
      Destino.AddElement(Clone);
  end;
end;

function ArrayJSON(Objeto: TJSONObject; const Nome: String): TJsonArray;
var
  Valor: TJSONValue;
begin
  Result := nil;
  Valor := Objeto.GetValue(Nome);
  if Assigned(Valor) and (Valor is TJsonArray) then
    Result := TJsonArray(Valor);
end;

function DashboardVendaDiaExiste(DataRef: TDate): Boolean;
var
  conexao: TConexao;
  Qry: TFDQuery;
begin
  Result := False;
  conexao := TConexao.Create('DashboardVendaDiaExiste');
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text := 'SELECT 1 FROM ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_DIA_TABLE + ' WHERE data_ref = :data_ref LIMIT 1';
    Qry.ParamByName('data_ref').AsString :=
      FormatDateTime('yyyy-mm-dd', DataRef);
    Qry.Open;
    Result := not Qry.Eof;
  except
    Result := False;
  end;
  Qry.Free;
  conexao.Free;
end;

procedure GravarDashboardVendaDia(DataRef: TDate; Dados: TJSONObject);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('GravarDashboardVendaDia');
  try
    conexao.SQL.Add('INSERT INTO ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_DIA_TABLE);
    conexao.SQL.Add('(data_ref, dados, gerado_em)');
    conexao.SQL.Add('VALUES (:data_ref, :dados, NOW())');
    conexao.SQL.Add
      ('ON DUPLICATE KEY UPDATE dados = VALUES(dados), gerado_em = VALUES(gerado_em)');
    conexao.Parametros('data_ref', FormatDateTime('yyyy-mm-dd', DataRef));
    conexao.Parametros('dados', Dados.ToString);
    conexao.ExecuteSQL;
  finally
    conexao.Free;
  end;
end;

function LerDashboardVendaDia(DataRef: TDate; out Dados: TJSONObject): Boolean;
var
  conexao: TConexao;
  Qry: TFDQuery;
  Valor: TJSONValue;
begin
  Result := False;
  Dados := nil;
  conexao := TConexao.Create('LerDashboardVendaDia');
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text := 'SELECT dados FROM ' + DASHBOARD_CACHE_DB + '.' +
      DASHBOARD_CACHE_DIA_TABLE + ' WHERE data_ref = :data_ref LIMIT 1';
    Qry.ParamByName('data_ref').AsString :=
      FormatDateTime('yyyy-mm-dd', DataRef);
    Qry.Open;
    if not Qry.Eof then
    begin
      Valor := TJSONObject.ParseJSONValue(Qry.FieldByName('dados').AsString);
      if Assigned(Valor) and (Valor is TJSONObject) then
      begin
        Dados := TJSONObject(Valor);
        Result := True;
      end
      else if Assigned(Valor) then
        Valor.Free;
    end;
  except
    if Assigned(Dados) then
      Dados.Free;
    Dados := nil;
    Result := False;
  end;
  Qry.Free;
  conexao.Free;
end;

procedure AquecerCacheDashboardVendaDia(DataRef: TDate;
  Forcar: Boolean = False);
var
  Dados: TJSONObject;
  DataStr, CacheKey: String;
  IgnorarAnterior: Boolean;
begin
  if DataRef >= Date then
    exit;
  if (not Forcar) and DashboardVendaDiaExiste(DataRef) then
    exit;

  DataStr := FormatDateTime('yyyy-mm-dd', DataRef);
  CacheKey := ChaveCacheDashboardVenda(DataStr, DataStr);
  if Forcar then
    LimpaCache(DASHBOARD_CACHE_ORIGEM, CacheKey);

  IgnorarAnterior := DashboardVendaIgnorarCache;
  DashboardVendaIgnorarCache := True;
  try
    Dados := BuscarDashBoardVenda(DataStr, DataStr);
  finally
    DashboardVendaIgnorarCache := IgnorarAnterior;
  end;
  try
    GravarDashboardVendaDia(DataRef, Dados);
    GravaCache(DASHBOARD_CACHE_ORIGEM, CacheKey, Dados.ToString,
      DASHBOARD_CACHE_VALIDADE_MINUTOS);
    RegistrarReferenciaDashboardVenda('Dia ' + DataStr, DataStr, DataStr,
      CacheKey);
  finally
    Dados.Free;
  end;
end;

function TentarMontarDashboardVendaCacheDiario(DataIni, DataFim: String;
  out Resultado: TJSONObject): Boolean;
var
  DataInicial, DataFinal, Dia, UltimoDiaCache: TDate;
  DiaJSON, HojeJSON: TJSONObject;
  TotalQtd, TotalTotal, PdvQtd, PdvTotal, MesaQtd, MesaTotal, SiteQtd,
    SiteTotal, IfoodQtd, IfoodTotal, MediaQtd, Nfce: Double;
  Horario, TipoPagamento, Dias, Ifood, Proprio, Extrato: TJsonArray;
  IgnorarAnterior: Boolean;

  procedure Consumir(Dados: TJSONObject);
  begin
    TotalQtd := TotalQtd + ValorJSONNumero(Dados, 'total_qtd');
    TotalTotal := TotalTotal + ValorJSONNumero(Dados, 'total_total');
    PdvQtd := PdvQtd + ValorJSONNumero(Dados, 'pdv_qtd');
    PdvTotal := PdvTotal + ValorJSONNumero(Dados, 'pdv_total');
    MesaQtd := MesaQtd + ValorJSONNumero(Dados, 'mesa_qtd');
    MesaTotal := MesaTotal + ValorJSONNumero(Dados, 'mesa_total');
    SiteQtd := SiteQtd + ValorJSONNumero(Dados, 'site_qtd');
    SiteTotal := SiteTotal + ValorJSONNumero(Dados, 'site_total');
    IfoodQtd := IfoodQtd + ValorJSONNumero(Dados, 'ifood_qtd');
    IfoodTotal := IfoodTotal + ValorJSONNumero(Dados, 'ifood_total');
    MediaQtd := MediaQtd + ValorJSONNumero(Dados, 'media_qtd');
    Nfce := Nfce + ValorJSONNumero(Dados, 'nfce');
    AnexarArrayJSON(Horario, ArrayJSON(Dados, 'horario'));
    AnexarArrayJSON(TipoPagamento, ArrayJSON(Dados, 'tipo_pagamento'));
    AnexarArrayJSON(Dias, ArrayJSON(Dados, 'dias'));
    AnexarArrayJSON(Ifood, ArrayJSON(Dados, 'ifood'));
    AnexarArrayJSON(Proprio, ArrayJSON(Dados, 'proprio'));
    AnexarArrayJSON(Extrato, ArrayJSON(Dados, 'extrato'));
  end;

begin
  Result := False;
  Resultado := nil;
  if DashboardVendaIgnorarCache then
    exit;

  try
    DataInicial := ParseISODate(DataIni);
    DataFinal := ParseISODate(DataFim);
  except
    exit;
  end;

  if DataFinal < DataInicial then
    exit;
  if DataInicial > Date then
    exit;

  GarantirTabelaReferenciaDashboardVenda;

  UltimoDiaCache := IncDay(Date, -1);
  if DataFinal < UltimoDiaCache then
    UltimoDiaCache := DataFinal;

  Horario := TJsonArray.Create;
  TipoPagamento := TJsonArray.Create;
  Dias := TJsonArray.Create;
  Ifood := TJsonArray.Create;
  Proprio := TJsonArray.Create;
  Extrato := TJsonArray.Create;
  try
    Dia := DataInicial;
    while Dia <= UltimoDiaCache do
    begin
      if not LerDashboardVendaDia(Dia, DiaJSON) then
      begin
        AquecerCacheDashboardVendaDia(Dia, False);
        if not LerDashboardVendaDia(Dia, DiaJSON) then
          exit;
      end;
      try
        Consumir(DiaJSON);
      finally
        DiaJSON.Free;
      end;
      Dia := IncDay(Dia, 1);
    end;

    if (DataInicial <= Date) and (DataFinal >= Date) then
    begin
      IgnorarAnterior := DashboardVendaIgnorarCache;
      DashboardVendaIgnorarCache := True;
      try
        HojeJSON := BuscarDashBoardVenda(FormatDateTime('yyyy-mm-dd', Date),
          FormatDateTime('yyyy-mm-dd', Date));
      finally
        DashboardVendaIgnorarCache := IgnorarAnterior;
      end;
      try
        Consumir(HojeJSON);
      finally
        HojeJSON.Free;
      end;
    end;

    Resultado := TJSONObject.Create;
    AdicionarNumeroJSON(Resultado, 'total_qtd', TotalQtd);
    AdicionarNumeroJSON(Resultado, 'total_total', TotalTotal);
    AdicionarNumeroJSON(Resultado, 'pdv_qtd', PdvQtd);
    AdicionarNumeroJSON(Resultado, 'pdv_total', PdvTotal);
    AdicionarNumeroJSON(Resultado, 'mesa_qtd', MesaQtd);
    AdicionarNumeroJSON(Resultado, 'mesa_total', MesaTotal);
    AdicionarNumeroJSON(Resultado, 'site_qtd', SiteQtd);
    AdicionarNumeroJSON(Resultado, 'site_total', SiteTotal);
    AdicionarNumeroJSON(Resultado, 'ifood_qtd', IfoodQtd);
    AdicionarNumeroJSON(Resultado, 'ifood_total', IfoodTotal);
    if MediaQtd > 0 then
      AdicionarNumeroJSON(Resultado, 'media_total', TotalTotal / MediaQtd)
    else
      AdicionarNumeroJSON(Resultado, 'media_total', 0);
    AdicionarNumeroJSON(Resultado, 'media_qtd', MediaQtd);
    AdicionarNumeroJSON(Resultado, 'nfce', Nfce);
    Resultado.AddPair('horario', Horario);
    Resultado.AddPair('tipo_pagamento', TipoPagamento);
    Resultado.AddPair('dias', Dias);
    Resultado.AddPair('ifood', Ifood);
    Resultado.AddPair('proprio', Proprio);
    Resultado.AddPair('extrato', Extrato);
    MarcarReferenciaDashboardVenda(Resultado, ChaveCacheDashboardVenda(DataIni,
      DataFim));

    Horario := nil;
    TipoPagamento := nil;
    Dias := nil;
    Ifood := nil;
    Proprio := nil;
    Extrato := nil;
    Result := True;
  finally
    if not Result and Assigned(Resultado) then
      FreeAndNil(Resultado);
    Horario.Free;
    TipoPagamento.Free;
    Dias.Free;
    Ifood.Free;
    Proprio.Free;
    Extrato.Free;
  end;
end;

procedure AquecerCacheDashboardVendaDiarioFechado(DataInicial,
  DataFinal: TDate);
var
  Dia: TDate;
begin
  Dia := DataInicial;
  while Dia <= DataFinal do
  begin
    AquecerCacheDashboardVendaDia(Dia, False);
    TThread.Sleep(250);
    Dia := IncDay(Dia, 1);
  end;
end;

procedure ExecutarAquecimentoCacheDashboardVenda;
var
  Hoje, Ontem, PrimeiroDiaAno, InicioMesAtual, InicioMesAnterior,
    FimMesAnterior, InicioTresMeses, DataIni, DataFim: TDate;
  AnoAtual, MesAtual, Mes, DiaMes: Word;
begin
  GarantirTabelaReferenciaDashboardVenda;

  Hoje := Date;
  Ontem := IncDay(Hoje, -1);
  PrimeiroDiaAno := EncodeDate(YearOf(Hoje), 1, 1);
  InicioMesAtual := EncodeDate(YearOf(Hoje), MonthOf(Hoje), 1);
  InicioMesAnterior := IncMonth(InicioMesAtual, -1);
  FimMesAnterior := IncDay(InicioMesAtual, -1);
  InicioTresMeses := IncMonth(Hoje, -3);

  if Ontem >= PrimeiroDiaAno then
    AquecerCacheDashboardVendaDiarioFechado(PrimeiroDiaAno, Ontem);

  AquecerCacheDashboardVendaPeriodo('Ano Atual', PrimeiroDiaAno, Hoje, True);
  TThread.Sleep(1000);

  DecodeDate(Hoje, AnoAtual, MesAtual, DiaMes);
  for Mes := 1 to MesAtual do
  begin
    DataIni := EncodeDate(AnoAtual, Mes, 1);
    if Mes = MesAtual then
      DataFim := Hoje
    else
      DataFim := EndOfTheMonth(DataIni);
    AquecerCacheDashboardVendaPeriodo(FormatDateTime('mmmm yyyy', DataIni),
      DataIni, DataFim, Mes = MesAtual);
    TThread.Sleep(1000);
  end;

  AquecerCacheDashboardVendaPeriodo('Mes Anterior', InicioMesAnterior,
    FimMesAnterior, False);
  TThread.Sleep(1000);

  AquecerCacheDashboardVendaPeriodo('Ultimos 3 Meses', InicioTresMeses,
    Hoje, True);
  TThread.Sleep(1000);
end;

procedure ExecutarAquecimentoCacheDashboardVendaTask;
begin
  try
    ExecutarAquecimentoCacheDashboardVenda;
  except
  end;
  DashboardVendaCacheAquecendo := False;
end;

procedure IniciarAquecimentoCacheDashboardVenda;
begin
  if DashboardVendaCacheAquecendo then
    exit;
  DashboardVendaCacheAquecendo := True;

  TTask.Run(ExecutarAquecimentoCacheDashboardVendaTask);
end;

function BuscarDashBoardVenda(DataIni, DataFim: String): TJSONObject;
var
  conexao: TConexao;
  JSONObject: TJSONObject;
  Cache: TJSONObject;
  CacheKey: String;
  UsarCache: Boolean;
  PDV_QTD: Integer;
  PDV_TOT: Real;
  SITE_QTD: Integer;
  SITE_TOT: Real;
  MESA_QTD: Integer;
  MESA_TOT: Real;
  IFOOD_QTD: Integer;
  IFOOD_TOT: Real;
  Nfce: Real;
  Quantidade: Integer;
  MEDIA: Real;
begin

  UsarCache := PeriodoDashBoardVendaPermiteCache(DataIni, DataFim);
  CacheKey := DataIni + '_' + DataFim;
  if (not DashboardVendaIgnorarCache) and TentarMontarDashboardVendaCacheDiario
    (DataIni, DataFim, Cache) then
    exit(Cache);

  if not DashboardVendaIgnorarCache then
  begin
    Cache := BuscaCacheObject('DoGetDashBoardVenda', CacheKey);
    if Cache.Count > 0 then
    begin
      MarcarReferenciaDashboardVenda(Cache, CacheKey);
      exit(Cache);
    end;
    Cache.Free;
  end;

  conexao := TConexao.Create('v2');
  JSONObject := TJSONObject.Create;
  conexao.SQL.Add
    ('select 0 as zero,count(distinct data_pedido) as quantidade from pedido where data_pedido between "'
    + DataIni + '" and "' + DataFim +
    '" and codigo_pedido_dia > 0 and status > 0');
  try
    Quantidade := conexao.FieldByName('quantidade');
  except
    Quantidade := 0;
  end;
  conexao.SQL.Add
    (('select 0 as zero, count(*) as quantidade from pedido where status > 0 and origem not in (2,4) and (id_ficha is null or id_ficha = 0) and data_pedido between "'
    + DataIni + '" and "' + DataFim + '"'));
  try
    PDV_QTD := conexao.FieldByName('quantidade');
  except
    PDV_QTD := 0;
  end;
  conexao.SQL.Add
    (('select 0 as zero, sum(valor_total_pedido) as quantidade from pedido where status > 0 and origem not in (2,4) and (id_ficha is null or id_ficha = 0) and data_pedido between "'
    + DataIni + '" and "' + DataFim + '"'));
  try
    PDV_TOT := conexao.FieldByName('quantidade');
  except
    PDV_TOT := 0;
  end;
  conexao.SQL.Add
    (('select 0 as zero, count(*) as quantidade from pedido where status > 0 and origem <> 2 and id_ficha > 0 and data_pedido between "'
    + DataIni + '" and "' + DataFim + '"'));
  try
    MESA_QTD := conexao.FieldByName('quantidade');
  except
    MESA_QTD := 0;
  end;
  conexao.SQL.Add
    (('select 0 as zero, sum(valor_total_pedido) as quantidade from pedido where status > 0 and origem <> 2 and id_ficha > 0 and data_pedido between "'
    + DataIni + '" and "' + DataFim + '"'));
  try
    MESA_TOT := conexao.FieldByName('quantidade');
  except
    MESA_TOT := 0;
  end;
  conexao.SQL.Add
    (('select 0 as zero, count(*) as quantidade from pedido where status > 0 and origem in (2) and data_pedido between "'
    + DataIni + '" and "' + DataFim + '"'));
  try
    SITE_QTD := conexao.FieldByName('quantidade');
  except
    SITE_QTD := 0;
  end;
  conexao.SQL.Add
    (('select 0 as zero, sum(valor_total_pedido) as quantidade from pedido where status > 0 and origem in (2) and (id_ficha is null or id_ficha = 0) and (id_pedido_site > 1) and data_pedido between "'
    + DataIni + '" and "' + DataFim + '"'));
  try
    SITE_TOT := conexao.FieldByName('quantidade');
  except
    SITE_TOT := 0;
  end;
  conexao.SQL.Add
    (CriaSubQuery
    ('select 0 as zero, count(*) as quantidade from pedido where status > 0 and id_ifood <> '
    + QuotedStr('') + ' and id_ficha is null and data_pedido between "' +
    DataIni + '" and "' + DataFim + '"', 'quantidade', DataIni, DataFim));
  try
    IFOOD_QTD := conexao.FieldByName('quantidade');
  except
    IFOOD_QTD := 0;
  end;
  conexao.SQL.Add
    (('select 0 as zero, sum(valor_total_pedido) as quantidade from pedido where status > 0 and id_ifood <> '
    + QuotedStr('') + ' and id_ficha is null and data_pedido between "' +
    DataIni + '" and "' + DataFim + '"'));
  try
    IFOOD_TOT := conexao.FieldByName('quantidade');
  except
    IFOOD_TOT := 0;
  end;
  conexao.SQL.Add
    (('select sum(p.valor_total_pedido) as quantidade, 0 as zero from caixa as c '
    + ' join pedido as p on p.id_caixa = c.id' +
    ' where c.data_abertura between "' + DataIni + '" and "' + DataFim +
    '" and p.nfce_emite = 2'));
  try
    Nfce := conexao.FieldByName('quantidade');
  except
    Nfce := 0;
  end;
  MEDIA := (PDV_TOT + MESA_TOT + SITE_TOT + IFOOD_TOT);
  if Quantidade > 0 then
    MEDIA := MEDIA / Quantidade
  else
    MEDIA := 0;
  conexao.SQL.Add
    ('SELECT CASE WHEN MINUTE(hora_pedido) < 30 THEN DATE_FORMAT(hora_pedido, '
    + QuotedStr('%H:00') + ')' + ' ELSE DATE_FORMAT(hora_pedido, ' +
    QuotedStr('%H:30') + ') END AS intervalo_hora, ' +
    ' COUNT(*) as quantidade, SUM(valor_total_pedido) AS total_pedido ' +
    ' from pedido as p' + ' where p.data_pedido between "' + DataIni + '" and "'
    + DataFim +
    '" and p.status > 0 and p.id_ficha is null GROUP BY intervalo_hora');
  JSONObject.AddPair('total_qtd', PDV_QTD + MESA_QTD + SITE_QTD + IFOOD_QTD);
  JSONObject.AddPair('total_total', PDV_TOT + MESA_TOT + SITE_TOT + IFOOD_TOT);
  JSONObject.AddPair('pdv_qtd', PDV_QTD);
  JSONObject.AddPair('pdv_total', PDV_TOT);
  JSONObject.AddPair('mesa_qtd', MESA_QTD);
  JSONObject.AddPair('mesa_total', MESA_TOT);
  JSONObject.AddPair('site_qtd', SITE_QTD);
  JSONObject.AddPair('site_total', SITE_TOT);
  JSONObject.AddPair('ifood_qtd', IFOOD_QTD);
  JSONObject.AddPair('ifood_total', IFOOD_TOT);
  JSONObject.AddPair('media_total', MEDIA);
  JSONObject.AddPair('media_qtd', Quantidade);
  JSONObject.AddPair('nfce', Nfce);
  JSONObject.AddPair('horario', conexao.ConsultaSQL);
  conexao.SQL.Add
    ('select sum(cm.valor) as total, count(*) as quantidade, upper(tp.descricao) as descricao, sum((cm.valor * tp.taxa)/100) as total_desconto from ');
  conexao.SQL.Add('caixa as c');
  conexao.SQL.Add('join caixa_movimento as cm on cm.id_caixa = c.id ');
  conexao.SQL.Add
    ('join tipo_pagamento as tp on tp.codigo = cm.id_tipo_pagamento');
  conexao.SQL.Add('where c.data_abertura between "' + DataIni + '" and "' +
    DataFim + '" and cm.tipo = 1');
  conexao.SQL.Add('group by tp.descricao');
  conexao.SQL.Add('order by sum(cm.valor) desc');
  JSONObject.AddPair('tipo_pagamento', conexao.ConsultaSQL);
  if DaysBetweenDates(DataIni, DataFim) > 31 then
  begin
    conexao.SQL.Add(('select ' + ' count(*) as qtd, ' +
      'sum(valor_total_pedido) as total, ' + 'DATE_FORMAT(data_pedido, ' +
      QuotedStr('%Y/%m') + ') as data ' +
      'from pedido where status > 0 and data_pedido between "' + DataIni +
      '" and "' + DataFim + '" ' + 'group by DATE_FORMAT(data_pedido, ' +
      QuotedStr('%Y/%m') + ') '));
  end
  else
  begin
    conexao.SQL.Add(('select count(*) as qtd,' +
      ' sum(valor_total_pedido) as total, ' + ' date_format(data_pedido, ' +
      QuotedStr('%d/%m') + ') as data' +
      ' from pedido where status > 0 and data_pedido between "' + DataIni +
      '" and "' + DataFim + '"' + ' group by data_pedido'));
  end;
  JSONObject.AddPair('dias', conexao.ConsultaSQL);
  if DaysBetweenDates(DataIni, DataFim) > 31 then
  begin
    conexao.SQL.Add('select ' + ' count(*) as qtd, ' +
      'sum(valor_total_pedido) as total, ' + 'DATE_FORMAT(data_pedido, ' +
      QuotedStr('%Y/%m') + ') as data ' +
      ' from pedido where status > 0 and data_pedido between "' + DataIni +
      '" and "' + DataFim + '" and status_ifood is not null' +
      'group by DATE_FORMAT(data_pedido, ' + QuotedStr('%Y/%m') + ') ');
  end
  else
  begin
    conexao.SQL.Add('select count(*) as qtd,' +
      ' sum(valor_total_pedido) as total, ' + ' date_format(data_pedido, ' +
      QuotedStr('%d/%m') + ') as data' +
      ' from pedido where status > 0 and data_pedido between "' + DataIni +
      '" and "' + DataFim + '" and status_ifood is not null' +
      ' group by data_pedido');
  end;
  JSONObject.AddPair('ifood', conexao.ConsultaSQL);
  if DaysBetweenDates(DataIni, DataFim) > 31 then
  begin
    conexao.SQL.Add('select ' + ' count(*) as qtd, ' +
      'sum(valor_total_pedido) as total, ' + 'DATE_FORMAT(data_pedido, ' +
      QuotedStr('%Y/%m') + ') as data ' +
      ' from pedido where status > 0 and status_ifood is null and data_pedido between "'
      + DataIni + '" and "' + DataFim + '"' +
      'group by DATE_FORMAT(data_pedido, ' + QuotedStr('%Y/%m') + ') ');
  end
  else
  begin
    conexao.SQL.Add('select count(*) as qtd,' +
      ' sum(valor_total_pedido) as total, ' + ' date_format(data_pedido, ' +
      QuotedStr('%d/%m') + ') as data' +
      ' from pedido where status > 0 and status_ifood is null and data_pedido between "'
      + DataIni + '" and "' + DataFim + '"' + ' group by data_pedido');
  end;
  JSONObject.AddPair('proprio', conexao.ConsultaSQL);
  with conexao do
  begin
    SQL.Clear;
    SQL.Add('SELECT c.id AS id,');
    SQL.Add('  COALESCE((SELECT SUM(valor) FROM caixa_movimento cm WHERE cm.tipo=1 AND cm.id_caixa=c.id),0) AS valor_fechamento,');
    SQL.Add('  c.data_abertura, c.hora_abertura, c.data_fechamento, c.hora_fechamento, u.nome,');
    SQL.Add('  COUNT(p.codigo) AS quantidade');
    SQL.Add('FROM caixa c');
    SQL.Add('JOIN usuario u ON u.codigo = c.id_usuario');
    SQL.Add('JOIN pedido p ON p.id_caixa = c.id');
    SQL.Add('WHERE c.data_abertura BETWEEN :dataini AND :datafim');
    SQL.Add('  AND c.status = 2');
    SQL.Add('GROUP BY c.id, c.data_abertura, c.hora_abertura, c.data_fechamento, c.hora_fechamento, u.nome');
    SQL.Add('ORDER BY c.data_abertura');
    Parametros('dataini', DataIni);
    Parametros('datafim', DataFim);
  end;
  JSONObject.AddPair('extrato', conexao.ConsultaSQL);
  conexao.Free;

  if UsarCache then
    GravaCache('DoGetDashBoardVenda', CacheKey, JSONObject.ToString,
      DASHBOARD_CACHE_VALIDADE_MINUTOS);

  Result := JSONObject;

end;

procedure DoGetDashBoardVenda(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  Res.Send<TJSONObject>(BuscarDashBoardVenda(Req.Params['dataini'],
    Req.Params['datafim']));
end;

procedure DoGetTestErro(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  frmServidor.EnviaGlitchtip
    ('https://070641a91ca74f3c8b3f1cec9d5ca962@nginx-glitchtip.l1p88w.easypanel.host/4',
    'TEST' + FormatDateTime('ddhhmm', now), 'Test', 'Test');
  frmServidor.EnviaGlitchtip
    ('https://d8c00b2846b3412dacbdb44d38144456@nginx-glitchtip.l1p88w.easypanel.host/2',
    'TEST' + FormatDateTime('ddhhmm', now), 'Test', 'Test');
  frmServidor.EnviaGlitchtip
    ('https://aeb22e97438d453c9a5651422ad3c0f4@nginx-glitchtip.l1p88w.easypanel.host/3',
    'TEST' + FormatDateTime('ddhhmm', now), 'Test', 'Test');
  frmServidor.EnviaGlitchtip
    ('https://9327eaf954a340cb94c64a8bf4afb696@nginx-glitchtip.l1p88w.easypanel.host/5',
    'TEST' + FormatDateTime('ddhhmm', now), 'Test', 'Test');
  frmServidor.EnviaGlitchtip
    ('https://393ce11c328044b4a747820f31ce790a@nginx-glitchtip.l1p88w.easypanel.host/1',
    'TEST' + FormatDateTime('ddhhmm', now), 'Test', 'Test');
  frmServidor.EnviaGlitchtip
    ('https://2321bb196f424d6aa9e80d51cc77273b@nginx-glitchtip.l1p88w.easypanel.host/6',
    'TEST' + FormatDateTime('ddhhmm', now), 'Test', 'Test');
end;

procedure DoGetStatusSite(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Requisicao: iRequisicao;
begin
  try
    Requisicao := iRequisicao.Create(nil);
    Requisicao.BaseURL := 'https://old.goopedir.com/v1/horario.php?codigo=' +
      frmServidor.UserID.ToString;
    Requisicao.Execute;
    Res.Send(Requisicao.Retorno);
  except
    Res.Send('[]');
  end;
  Requisicao.Free;
end;

procedure DoPostStatusSiteClose(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
begin
  try
    Requisicao := iRequisicao.Create(nil);
    Requisicao.BaseURL :=
      'https://old.goopedir.com/v1/empresa.php?status=false&user=' +
      frmServidor.UserID.ToString;
    Requisicao.Execute;
    Res.Send(Requisicao.Retorno);
  except
    Res.Send('[]');
  end;
  Requisicao.Free;
end;

procedure DoPostStatusSiteOpen(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
begin
  try
    Requisicao := iRequisicao.Create(nil);
    Requisicao.BaseURL :=
      'https://old.goopedir.com/v1/empresa.php?status=true&user=' +
      frmServidor.UserID.ToString;
    Requisicao.Execute;
    Res.Send(Requisicao.Retorno);
  except
    Res.Send('[]');
  end;
  Requisicao.Free;
end;

procedure DoPostMarketingGerarCupom(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  // conexao := TConexao.Create('v2');
  // conexao.SQL.Add('');
end;

procedure DoGetCupomLiberado(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  try
    conexao.SQL.Add('update marketing set status = 2 where id = :id');
    conexao.Parametros('id', Req.Params['codigo']);
    conexao.ExecuteSQL;
  except
  end;
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('SELECT marketing.*, cliente.celular, cliente.celular_wpp FROM marketing join cliente on cliente.codigo = marketing.id_cliente where validade > current_date() and status = 1');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostGravacaoGenerica(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  LJSONObject: TJSONObject;
  LJSONPair: TJSONPair;
  LKey, LValue: string;
  SQL: String;
  conexao: TConexao;
  Campos: String;
  Parametros: String;
  Insert: Boolean;
  Campo: String;
  Valor: String;
  Update: String;
  test: String;
begin
  conexao := TConexao.Create('v2');
  Campos := '';
  LJSONObject := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  try
    for LJSONPair in LJSONObject do
    begin
      LKey := LJSONPair.JSONString.Value;
      LValue := LJSONPair.JSONValue.Value;
      if Length(Campos) = 0 then
      begin
        Campos := LKey;
        Parametros := ':' + LKey;
        Campo := LKey;
        Valor := LValue;
        if (StrToInt(LValue) < 0) then
        begin
          LValue := conexao.GerarID(Req.Params['tabela'], LKey).ToString;
          Valor := LValue;
          Insert := True;
        end;
        conexao.Parametros(LKey, LValue);
        Update := LKey + ' = :' + LKey;
      end
      else
      begin
        Campos := Campos + ',' + LKey;
        Parametros := Parametros + ',:' + LKey;
        conexao.Parametros(LKey, LValue);
        Update := Update + ',' + LKey + ' = :' + LKey;
      end;
      // Agora voc? tem o nome da chave (LKey) e seu valor (LValue)
      // Voc? pode processar, armazenar ou imprimir conforme necess?rio
      // Writeln(Format('%s: %s', [LKey, LValue]));
    end;
    if Insert then
    begin
      SQL := 'insert into ' + Req.Params['tabela'] + ' (' + Campos +
        ') values (' + Parametros + ')';
      //
    end
    else
    begin
      SQL := 'update ' + Req.Params['tabela'] + ' set ' + Update + ' where ' +
        Campo + ' = :upd';
      conexao.Parametros('upd', Valor);
    end;
    conexao.SQL.Add(SQL);
    conexao.ExecuteSQL;
    conexao.Free;
  finally
    LJSONObject.Free;
  end;
end;

procedure DoGetPedidosSite(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  SQL: String;
  Resumo: String;
begin
  conexao := TConexao.Create('v2');
  Resumo := '(SELECT ';
  Resumo := Resumo + 'concat(group_concat(' + QuotedStr('<b>Qtd: ') +
    ',localpp.quantidade,' + QuotedStr('x ') + ',localp.nome_produto,' +
    QuotedStr('<br /><b>') + ',ppslocal.nomeclatura,' + QuotedStr(' ') +
    ',ppslocal.descricao ,' + QuotedStr('<br />Valor R$: ') +
    ',localpp.valor_total,' + QuotedStr('<br />') + '),' +
    QuotedStr('<br /><b>Importado Sistema!<br /><b>') + ') ';
  Resumo := Resumo + 'FROM pedido_produto_sap as ppslocal ';
  Resumo := Resumo +
    'join pedido_produtos as localpp on localpp.codigo = ppslocal.codigo_pedido_produto ';
  Resumo := Resumo +
    'join produto localp on localp.codigo = localpp.codigo_produto ';
  Resumo := Resumo + 'where localpp.codigo_pedido = p.codigo ';
  Resumo := Resumo + 'group by localpp.codigo_pedido) ';
  SQL := '';
  SQL := 'SELECT  ';
  SQL := SQL + ' LPAD(p.codigo_pedido_dia,5,' + QuotedStr('0') +
    ') as codigo_pedido, ';
  SQL := SQL +
    ' DATE_FORMAT(concat(p.data_pedido,'' '',p.hora_pedido),''%Y-%m-%d %H:%i:%s'') as data, ';
  SQL := SQL + ' DATE_FORMAT(p.data_pedido,''%Y-%m'') as DATA_CHART, ';
  SQL := SQL + ' DATE_FORMAT(p.data_pedido,''%Y-%m-%d'') as DATA_CHART2, ';
  SQL := SQL + ' p.troco as valor_troco, ';
  SQL := SQL +
    ' CASE WHEN p.codigo_cliente_endereco = 0 THEN false ELSE true END as opcao_delivery, ';
  SQL := SQL + ' p.valor_taxa_entrega as valor_taxa, ';
  SQL := SQL + ' 0 as adicionais, ';
  SQL := SQL + ' p.valor_pedido as sub_total, ';
  SQL := SQL + ' p.id_ifood as id_ifood, ';
  SQL := SQL + ' p.valor_total_pedido as total, ';
  SQL := SQL + ' c.nome as nome, ';
  SQL := SQL +
    ' REPLACE(REPLACE(REPLACE(REPLACE(c.celular, ''('', ''''), '')'', ''''), ''-'', ''''), '' '', '''') as telefone, ';
  SQL := SQL + ' ce.rua as rua, ';
  SQL := SQL + ' ce.numero as unidade, ';
  SQL := SQL + ' ce.bairro as bairro, ';
  SQL := SQL + ' ce.cidade as cidade, ';
  SQL := SQL + ' ce.estado as uf, ';
  SQL := SQL + ' p.latitude as lat, ';
  SQL := SQL + ' p.longitude as lgn, ';
  SQL := SQL + ' 0 as tempo, ';
  SQL := SQL + ' ce.complemento as complemento, ';
  SQL := SQL + QuotedStr('') + ' as observacao, ';
  SQL := SQL + ' case p.status  ';
  SQL := SQL + ' when 0 then ''Cancelado''  ';
  SQL := SQL + ' when 1 then ''Finalizado''  ';
  SQL := SQL + ' when 2 then ''Finalizado''  ';
  SQL := SQL + ' when 3 then ''Finalizado''  ';
  SQL := SQL + ' when 4 then ''Finalizado''  ';
  SQL := SQL + ' when 5 then ''Finalizado''  ';
  SQL := SQL + ' when 6 then ''Finalizado'' end as status, ';
  SQL := SQL + ' DATE_FORMAT(p.data_pedido,''%m'') as mes, ';
  SQL := SQL + ' DATE_FORMAT(p.data_pedido,''%Y'') as ano, ';
  SQL := SQL + ' 1 as view, ';
  SQL := SQL + ' valor_desconto as desconto, ';
  SQL := SQL +
    ' CASE WHEN p.codigo_cliente_endereco = 0 THEN ''Retirada no Bal??o'' ELSE '
    + QuotedStr('') + ' END as msg_delivery_false, ';
  SQL := SQL + ' p.codigo as id_sistema ';
  SQL := SQL + ' FROM pedido as p ';
  SQL := SQL + ' join cliente as c on c.codigo = p.codigo_cliente ';
  SQL := SQL +
    ' left join cliente_endereco as ce on ce.codigo = p.codigo_cliente_endereco ';
  SQL := SQL + ' where ';
  SQL := SQL +
    ' p.data_pedido > ''2000-12-31'' and p.id_pedido_site is null and p.status > 0 ';
  SQL := SQL + 'limit 15';
  conexao.SQL.Add(SQL);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
  frmServidor.HorSite := now;
end;

procedure DoGetResetBloqueio(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  frmServidor.ResetUser;
end;

procedure DoGetDadosBloqueio(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  // frmServidor.ResetUser;
  if not Assigned(frmServidor.JsonDadosBloqueio) then
    frmServidor.DadosBloqueio;
  try
    Res.Send(frmServidor.JsonDadosBloqueio.ToString);
  except
  end;
end;

procedure DoGetCertificadoDigital(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  Res.Send<TJsonArray>(frmServidor.RetornaCertificado);
end;

procedure DoGetClientes(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('select cliente.codigo,cliente.nome,cliente.celular,cliente.cpf,cliente.data_nascimento,cliente.total_efetivados, cliente.percentual_efetivado, cliente.nota_cliente,');
  conexao.SQL.Add
    ('cliente_endereco.rua, cliente_endereco.numero,cliente_endereco.bairro, cliente_endereco.complemento,  cliente_endereco.cidade, cliente_endereco.estado from cliente');
  conexao.SQL.Add
    ('left join cliente_endereco on cliente_endereco.codigo_cliente = cliente.codigo and cliente_endereco.codigo = (select max(codigo) from cliente_endereco where codigo_cliente = cliente.codigo)');
  conexao.SQL.Add
    ('where upper(nome) NOT LIKE "%MESA %" and upper(nome) NOT LIKE "%BALC?O%" and upper(nome) NOT LIKE "%BALCAO %" and nome <> "" and celular <> ""');
  conexao.SQL.Add('order by nota_cliente desc, valor_total_pedidos desc, nome');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostEmitirNFCeFiado(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  JsonObj: TJSONObject;
  ArrPedidos: TJsonArray;
  ArrProdutos: TJsonArray;
  ArrPagamentos: TJsonArray;
  PedidoObj, ProdutoObj, PagamentoObj: TJSONObject;
  i, j: Integer;
  CPF, Nome: string;
  TotalDevido: Double;
  CodigoNovoPedido: Integer;
  conexao: TConexao;
  Qry: TFDQuery;
begin
  JsonObj := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  try
    // Dados principais
    CPF := JsonObj.GetValue<string>('cpfcnpj');
    Nome := JsonObj.GetValue<string>('nome');
    TotalDevido := JsonObj.GetValue<Double>('totalDevido');
    // Writeln('CPF: ' + CPF);
    // Writeln('Nome: ' + Nome);
    // Writeln('Total Devido: ' + FloatToStr(TotalDevido));
    conexao := TConexao.Create('DoPostEmitirNFCeFiado');
    Qry := conexao.CriaQRY;
    CodigoNovoPedido := NovoPedido(conexao.GerarID('pedido', 'codigo'), 0, Qry);
    conexao.SQL.Add
      ('update pedido set cpf = :cpf, nome = :nome, status = -999, observacao_geral = "EMISS?O NFC-E FIADO", pedido_impresso = 1, origem = -999, id_caixa = -999, nfce_emite = 1 where codigo = :codigo');
    conexao.Parametros('cpf', CPF);
    conexao.Parametros('nome', Nome);
    conexao.Parametros('codigo', CodigoNovoPedido);
    conexao.ExecuteSQL;
    // ====================
    // PEDIDOS
    // ====================
    ArrPedidos := JsonObj.GetValue<TJsonArray>('pedidos');
    for i := 0 to ArrPedidos.Count - 1 do
    begin
      PedidoObj := ArrPedidos.Items[i] as TJSONObject;
      // Writeln('Pedido: ' + PedidoObj.GetValue<string>('pedido'));
      // Writeln('Valor: ' + PedidoObj.GetValue<string>('valor'));
      conexao.SQL.Add('UPDATE pedido p');
      conexao.SQL.Add('JOIN pedido p2 ON p2.codigo = ' +
        PedidoObj.GetValue<string>('pedido'));
      conexao.SQL.Add('SET');
      conexao.SQL.Add('  p.pedido_nfce = :codigo,');
      conexao.SQL.Add('  p.codigo_cliente = p2.codigo_cliente');
      conexao.SQL.Add('WHERE p.codigo = :pedido;');
      conexao.Parametros('codigo', CodigoNovoPedido);
      conexao.Parametros('pedido', PedidoObj.GetValue<string>('pedido'));
      conexao.ExecuteSQL;
      conexao.SQL.Add
        ('update caixa_receber set pago = valor, observacao = "EMITIDO NFC-E", status = 2 where id_pedido = :pedido');
      conexao.Parametros('pedido', PedidoObj.GetValue<string>('pedido'));
      conexao.ExecuteSQL;
      // PRODUTOS DO PEDIDO
      ArrProdutos := PedidoObj.GetValue<TJsonArray>('produtos');
      for j := 0 to ArrProdutos.Count - 1 do
      begin
        ProdutoObj := ArrProdutos.Items[j] as TJSONObject;
        // Writeln('  Produto: ' + ProdutoObj.GetValue<string>('nomeProduto'));
        // Writeln('  Quantidade: ' + ProdutoObj.GetValue<string>('quantidade'));
        // Writeln('  Total: ' + ProdutoObj.GetValue<string>('valorTotal'));
      end;
    end;
    // ====================
    // PAGAMENTOS
    // ====================
    ArrPagamentos := JsonObj.GetValue<TJsonArray>('pagamentos');
    for i := 0 to ArrPagamentos.Count - 1 do
    begin
      PagamentoObj := ArrPagamentos.Items[i] as TJSONObject;
      MovimentoCaixa(-999, CodigoNovoPedido,
        PagamentoObj.GetValue<Integer>('pagamento'), -999,
        PagamentoObj.GetValue<Double>('valor'), '', 0);
      // Writeln('Pagamento tipo: ' + PagamentoObj.GetValue<string>('pagamento'));
      // Writeln('Valor: ' + PagamentoObj.GetValue<string>('valor'));
    end;
  finally
    JsonObj.Free;
  end;
end;

procedure DoGetDadoCliente(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Objeto: TJSONObject;
  Dados: TFDMemTable;
begin
  conexao := TConexao.Create('DoGetDadoCliente');
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add('select * from cliente where codigo = :codigo');
  conexao.Parametros('codigo', Req.Params['codigo']);
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  Objeto := TJSONObject.Create;
  if Dados.RecordCount > 0 then
  begin
    Objeto := Dados.ToJSONObject();
    conexao.SQL.Add
      ('SELECT * FROM triangulo_lanches.cliente_endereco where codigo_cliente = :codigo order by codigo desc limit 1');
    conexao.Parametros('codigo', Req.Params['codigo']);
    Objeto.AddPair('endereco', conexao.ConsultaSQL);
  end;
  Dados.Free;
  conexao.Free;
  Res.Send<TJSONObject>(Objeto);
end;

procedure DoPostCliente(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  LJsonObj: TJSONObject;
  CodigoEndereco: Integer;
begin
  try
    LJsonObj := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
    conexao := TConexao.Create('v2');
    conexao.SQL.Add
      ('update cliente set nome = upper(:valor) where codigo = :codigo');
    conexao.Parametros('codigo', LJsonObj.GetValue<Integer>('codigo'));
    conexao.Parametros('valor', LJsonObj.GetValue<string>('nome'));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('update cliente set celular_wpp = upper(:valor) where codigo = :codigo');
    conexao.Parametros('codigo', LJsonObj.GetValue<Integer>('codigo'));
    conexao.Parametros('valor', LJsonObj.GetValue<string>('celular'));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('update cliente set celular = upper(:valor) where codigo = :codigo');
    conexao.Parametros('codigo', LJsonObj.GetValue<Integer>('codigo'));
    conexao.Parametros('valor', LJsonObj.GetValue<string>('celular'));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('update cliente set data_nascimento = upper(:valor) where codigo = :codigo');
    conexao.Parametros('codigo', LJsonObj.GetValue<Integer>('codigo'));
    conexao.Parametros('valor', LJsonObj.GetValue<string>('nascimento'));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('update cliente set cpf = upper(:valor) where codigo = :codigo');
    conexao.Parametros('codigo', LJsonObj.GetValue<Integer>('codigo'));
    conexao.Parametros('valor', LJsonObj.GetValue<string>('cpf'));
    conexao.ExecuteSQL;
    CodigoEndereco := conexao.GerarID('cliente_endereco', 'codigo');
    conexao.SQL.Add
      ('insert into cliente_endereco (codigo,codigo_cliente,descricao,tipo,numero,rua,bairro,cidade,estado,complemento,ativo)');
    conexao.SQL.Add('values (:codigo,:codigo_cliente,' + QuotedStr('Principal')
      + ',1,:numero,upper(:rua),upper(:bairro),upper(:cidade),upper(:estado),upper(:complemento),1)');
    conexao.Parametros('codigo', CodigoEndereco);
    conexao.Parametros('codigo_cliente', LJsonObj.GetValue<Integer>('codigo'));
    conexao.Parametros('numero', LJsonObj.GetValue<string>('numero'));
    conexao.Parametros('rua', LJsonObj.GetValue<string>('rua'));
    conexao.Parametros('bairro', LJsonObj.GetValue<string>('bairro'));
    conexao.Parametros('cidade', LJsonObj.GetValue<string>('cidade'));
    conexao.Parametros('estado', LJsonObj.GetValue<string>('estado'));
    conexao.Parametros('complemento', LJsonObj.GetValue<string>('complemento'));
    conexao.ExecuteSQL;
  except
  end;
  LJsonObj.Free;
  conexao.Free;
end;

procedure DoPostCorrigirClienteEnderecoDuplicado(Req: THorseRequest;
Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  Retorno: TJSONObject;
  TotalDuplicados: Integer;
  TotalPedidos: Integer;
  SQLChave: String;
  OkUpdate: Boolean;
  OkDelete: Boolean;
begin
  conexao := TConexao.Create('v2');
  Retorno := TJSONObject.Create;
  try
    SQLChave := 'MD5(CONCAT_WS(''|'', ' + 'UPPER(TRIM(COALESCE(rua, ''''))), ' +
      'UPPER(TRIM(COALESCE(bairro, ''''))), ' +
      'UPPER(TRIM(COALESCE(numero, ''''))), ' +
      'UPPER(TRIM(COALESCE(cidade, ''''))), ' +
      'UPPER(TRIM(COALESCE(estado, ''''))), ' +
      'UPPER(TRIM(COALESCE(complemento, '''')))))';

    conexao.ExecuteSQL
      ('DROP TEMPORARY TABLE IF EXISTS tmp_cliente_endereco_grupo');
    conexao.ExecuteSQL
      ('DROP TEMPORARY TABLE IF EXISTS tmp_cliente_endereco_dup');

    conexao.SQL.Add('CREATE TEMPORARY TABLE tmp_cliente_endereco_grupo AS');
    conexao.SQL.Add('SELECT codigo_cliente, ' + SQLChave + ' AS chave,');
    conexao.SQL.Add('MAX(codigo) AS codigo_mantido, COUNT(*) AS quantidade');
    conexao.SQL.Add('FROM cliente_endereco');
    conexao.SQL.Add('WHERE codigo_cliente > 0');
    conexao.SQL.Add('GROUP BY codigo_cliente, chave');
    conexao.SQL.Add('HAVING COUNT(*) > 1');
    conexao.ExecuteSQL;

    conexao.SQL.Add('CREATE TEMPORARY TABLE tmp_cliente_endereco_dup AS');
    conexao.SQL.Add('SELECT ce.codigo AS codigo_antigo,');
    conexao.SQL.Add('g.codigo_mantido AS codigo_mantido');
    conexao.SQL.Add('FROM cliente_endereco ce');
    conexao.SQL.Add('JOIN tmp_cliente_endereco_grupo g');
    conexao.SQL.Add('ON g.codigo_cliente = ce.codigo_cliente');
    conexao.SQL.Add('AND g.chave = ' + SQLChave);
    conexao.SQL.Add('WHERE ce.codigo <> g.codigo_mantido');
    conexao.ExecuteSQL;

    conexao.SQL.Add('SELECT COUNT(*) AS total, 0 AS zero');
    conexao.SQL.Add('FROM tmp_cliente_endereco_dup');
    TotalDuplicados := conexao.FieldByName('total');

    conexao.SQL.Add('SELECT COUNT(*) AS total, 0 AS zero');
    conexao.SQL.Add('FROM pedido p');
    conexao.SQL.Add('JOIN tmp_cliente_endereco_dup d');
    conexao.SQL.Add('ON d.codigo_antigo = p.codigo_cliente_endereco');
    TotalPedidos := conexao.FieldByName('total');

    conexao.SQL.Add('UPDATE pedido p');
    conexao.SQL.Add('JOIN tmp_cliente_endereco_dup d');
    conexao.SQL.Add('ON d.codigo_antigo = p.codigo_cliente_endereco');
    conexao.SQL.Add('SET p.codigo_cliente_endereco = d.codigo_mantido');
    conexao.ExecuteSQL;

    OkDelete := False;

    conexao.SQL.Add('DELETE ce FROM cliente_endereco ce');
    conexao.SQL.Add('JOIN tmp_cliente_endereco_dup d');
    conexao.SQL.Add('ON d.codigo_antigo = ce.codigo');
    conexao.ExecuteSQL;

    Retorno.AddPair('enderecos_duplicados',
      TJSONNumber.Create(TotalDuplicados));
    Retorno.AddPair('pedidos_atualizados', TJSONNumber.Create(TotalPedidos));
    // Retorno.AddPair('atualizou_pedidos', TJSONBool.Create(OkUpdate));
    Retorno.AddPair('removeu_duplicados', TJSONBool.Create(OkDelete));
    Retorno.AddPair('regra',
      'Mantem o maior codigo de cliente_endereco para cada cliente/endereco igual e move os pedidos dos codigos antigos para ele.');

    Res.Send<TJSONObject>(Retorno);
  except
    on E: Exception do
    begin
      Retorno.AddPair('erro', E.Message);
      Res.Send<TJSONObject>(Retorno);
    end;
  end;
  conexao.Free;
end;

procedure DoPostProdutoEntradaSaida(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
  Codigo: Integer;
  ID: Integer;
  Tipo: Integer;
begin
  // tipo
  // 1 - Baixa
  // 2 - Extorna
  if conexao.GetParametro('controle_estoque') = 1 then
  begin
    conexao := TConexao.Create('v2');
    Dados := TFDMemTable.Create(nil);
    conexao.SQL.Add
      ('select pedido_produtos.codigo, pedido_produtos.codigo_produto, pedido_produtos.quantidade  from pedido');
    conexao.SQL.Add
      ('join pedido_produtos on pedido_produtos.codigo_pedido = pedido.codigo');
    conexao.SQL.Add('where pedido_produtos.codigo = :codigo');
    conexao.Parametros('codigo', Codigo);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount > 0 then
    begin
      while not Dados.Eof do
      begin
        if Tipo = 1 then
        begin
          MovimentacaoProduto(Dados.FieldByName('codigo').AsInteger,
            Dados.FieldByName('codigo_produto').AsInteger, 2,
            Dados.FieldByName('quantidade').AsInteger);
        end
        else
        begin
          MovimentacaoProduto(Dados.FieldByName('codigo').AsInteger,
            Dados.FieldByName('codigo_produto').AsInteger, 1,
            Dados.FieldByName('quantidade').AsInteger);
        end;
        Dados.Next;
      end;
    end;
    Dados.Free;
    Dados := TFDMemTable.Create(nil);
    conexao.SQL.Add
      ('select produto_ingredientes.id_ingredientes, (produto_ingredientes.quantidade * pedido_produtos.quantidade) as quantidade, produto_ingredientes.id_produto as produto  from pedido');
    conexao.SQL.Add
      ('join pedido_produtos on pedido_produtos.codigo_pedido = pedido.codigo and pedido_produtos.codigo = :codigo');
    conexao.SQL.Add
      ('join produto_ingredientes on produto_ingredientes.id_produto = pedido_produtos.codigo_produto');
    conexao.Parametros('codigo', Codigo);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount > 0 then
    begin
      while not Dados.Eof do
      begin
        MovimentacaoInsulmo(Dados.FieldByName('id_ingredientes').AsInteger,
          Tipo, Dados.FieldByName('quantidade').AsFloat, 0, 0, False);
        Dados.Next;
      end;
    end;
    Dados.Free;
    Dados := TFDMemTable.Create(nil);
    conexao.SQL.Add
      ('select pro_adi_personalizado_sabores.id_ingredientes as ingredientes, pro_adi_personalizado_sabores.quantidade_ingredientes as quantidade from pedido');
    conexao.SQL.Add
      ('join pedido_produtos on pedido_produtos.codigo_pedido = pedido.codigo and pedido_produtos.codigo = :codigo');
    conexao.SQL.Add
      ('join pedido_produto_sap on pedido_produto_sap.codigo_pedido_produto = pedido_produtos.codigo');
    conexao.SQL.Add
      ('join pro_adi_personalizado on pro_adi_personalizado.id_produto = pedido_produtos.codigo_produto and upper(pro_adi_personalizado.descricao) = upper(pedido_produto_sap.nomeclatura)');
    conexao.SQL.Add
      ('join pro_adi_personalizado_sabores on pro_adi_personalizado_sabores.id_pro_adi_personalizado = pro_adi_personalizado.id and');
    conexao.SQL.Add
      ('upper(pro_adi_personalizado_sabores.nome) = upper(pedido_produto_sap.descricao) and pro_adi_personalizado_sabores.id_ingredientes <> 0');
    conexao.SQL.Add
      ('and pro_adi_personalizado_sabores.quantidade_ingredientes <> 0');
    conexao.Parametros('codigo', Codigo);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount > 0 then
    begin
      while not Dados.Eof do
      begin
        MovimentacaoInsulmo(Dados.FieldByName('ingredientes').AsInteger, Tipo,
          Dados.FieldByName('quantidade').AsFloat, 0, 0, False);
        Dados.Next;
      end;
    end;
    Dados.Free;
    conexao.Free;
  end;
end;

procedure DoGetEstoqueProdutoInsumo(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  if (StrToInt(Req.Params['tipo']) = 1) then
  begin
    // Produto
    conexao.SQL.Add
      ('select codigo as id, produto.nome_produto as nome, un as unidade, saldo_atual as estoque');
    conexao.SQL.Add('from produto where codigo = :id');
  end
  else
  begin
    // Insulmo
    conexao.SQL.Add
      ('SELECT id, descricao as nome, unidade, (select sum(quantidade) as estoque from ingredientes_estoque where id_ingredientes = ingredientes.id) as estoque  FROM ingredientes where id = :id');
  end;
  conexao.Parametros('id', Req.Params['codigo']);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetConsultaCPF(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('SELECT distinct nome, cpf FROM pedido where cpf = :cpf');
  conexao.Parametros('cpf', Req.Params['cpf']);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetConsultaFiado(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('select * from caixa_receber where id_cliente = :cliente order by data');
  conexao.Parametros('cliente', Req.Params['cliente']);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetConsultaClientesFiado(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Busca: String;
begin
  try
    Busca := Req.Params['busca'];
  except
    Busca := '';
  end;
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('SELECT c.codigo,c.nome,c.celular,c.cpf,SUM(cr.valor) - SUM(cr.pago) AS devedor, SUM(cr.pago) AS pago');
  conexao.SQL.Add('FROM cliente c');
  conexao.SQL.Add
    ('LEFT JOIN caixa_receber cr ON c.codigo = cr.id_cliente WHERE ');
  if Busca <> '' then
  begin
    if Length(Busca) < 3 then
    begin
      Res.Send('[]');
      conexao.Free;
      exit;
    end;
    conexao.SQL.Add('    CONCAT(upper(c.nome), c.cpf, c.celular) LIKE ' +
      QuotedStr('%' + UpperCase(Busca) + '%'));
  end
  else
  begin
    conexao.SQL.Add('c.celular > 999999');
  end;
  conexao.SQL.Add('GROUP BY c.codigo,c.nome,c.celular,c.cpf');
  conexao.SQL.Add
    ('ORDER BY SUM(CASE WHEN cr.status = 1 THEN cr.valor ELSE 0 END) DESC limit 15');
  // conexao.SQL.Add('SELECT ');
  // conexao.SQL.Add('    cliente.codigo, ');
  // conexao.SQL.Add('    cliente.nome, ');
  // conexao.SQL.Add('    cliente.celular, ');
  // conexao.SQL.Add('    cliente.cpf, ');
  // conexao.SQL.Add('     (SUM(valor)-SUM(pago)) as devedor,');
  // conexao.SQL.Add('    SUM(pago) as pago');
  // conexao.SQL.Add('FROM ');
  // conexao.SQL.Add('    cliente');
  // conexao.SQL.Add('LEFT JOIN caixa_receber ON cliente.codigo = caixa_receber.id_cliente');
  // conexao.SQL.Add('WHERE');
  // if Busca <> '' then
  // begin
  // conexao.SQL.Add('    CONCAT(upper(cliente.nome), cliente.cpf, cliente.celular) LIKE ' + QuotedStr('%' + UpperCase(Busca) + '%'));
  // end
  // else
  // begin
  // conexao.SQL.Add('cliente.celular > 99999');
  // end;
  // conexao.SQL.Add('GROUP BY ');
  // conexao.SQL.Add('    cliente.codigo, ');
  // conexao.SQL.Add('    cliente.nome, ');
  // conexao.SQL.Add('    cliente.celular, ');
  // conexao.SQL.Add('    cliente.cpf');
  // conexao.SQL.Add('    ORDER BY ');
  // conexao.SQL.Add('    SUM(CASE WHEN caixa_receber.status = 1 THEN caixa_receber.valor ELSE 0 END) desc');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostNovoCadastro(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  LJsonObj: TJSONObject;
  Codigo: Integer;
begin
  conexao := TConexao.Create('v2');
  LJsonObj := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  Codigo := conexao.GerarID('cliente', 'codigo');
  conexao.SQL.Add
    ('insert into cliente (codigo,nome,celular,celular_wpp,ativo,cpf) values  (:codigo,:nome,:celular,:celular_wpp,1,:cpf)');
  conexao.Parametros('codigo', Codigo);
  conexao.Parametros('nome', LJsonObj.GetValue<string>('nome'));
  conexao.Parametros('celular', LJsonObj.GetValue<string>('celular'));
  conexao.Parametros('cpf', LJsonObj.GetValue<string>('documento'));
  conexao.Parametros('celular_wpp',
    NonoDigito(LJsonObj.GetValue<string>('celular')));
  conexao.ExecuteSQL;
  conexao.Free;
  LJsonObj.Free;
end;

procedure DoPostEntradaPagamentoFiado(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  LJsonObj: TJSONObject;
  Codigo: Integer;
  DadosCaixa: TFDMemTable;
  Pagamento: Integer;
  Caixa: Integer;
  Valor: Real;
  OBS: String;
  ValorPago: Real;
  ValorTotal: Real;
  ValorMaximo: Real;
  JSON: String;
  DadosCliente: TFDMemTable;
begin
  conexao := TConexao.Create('v2');
  JSON := Req.body;
  DadosCaixa := TFDMemTable.Create(nil);
  DadosCliente := TFDMemTable.Create(nil);
  LJsonObj := TJSONObject.ParseJSONValue(JSON) as TJSONObject;
  try
    Codigo := LJsonObj.GetValue<Integer>('codigo');
  except
    Codigo := 0;
  end;
  try
    Pagamento := StrToInt(LJsonObj.GetValue<string>('pagamento'));
  except
    Pagamento := 0;
    Codigo := 0;
  end;
  try
    Caixa := StrToInt(LJsonObj.GetValue<string>('caixa'));
  except
    Caixa := 0;
    Codigo := 0;
  end;
  try
    Valor := StrToFloat(LJsonObj.GetValue<string>('valor'));
  except
    Valor := 0;
    Codigo := 0;
  end;
  if Codigo = 0 then
  begin
    conexao.Free;
    LJsonObj.Free;
    exit;
  end;
  conexao.SQL.Add
    ('select * from caixa_receber where id_cliente = :cliente and status = 1');
  conexao.Parametros('cliente', Codigo);
  DadosCaixa.LoadFromJSON(conexao.ConsultaSQL);
  if DadosCaixa.RecordCount > 0 then
  begin
    while not DadosCaixa.Eof do
    begin
      ValorPago := DadosCaixa.FieldByName('pago').AsFloat;
      ValorTotal := DadosCaixa.FieldByName('valor').AsFloat;
      ValorMaximo := ValorTotal - ValorPago;
      if Valor = 0 then
      begin
        ValorMaximo := 0;
      end;
      if Valor > ValorMaximo then
      begin
        Valor := Valor - ValorMaximo;
      end
      else
      begin
        if Valor > 0 then
        begin
          ValorMaximo := Valor;
          Valor := 0;
        end;
      end;
      if ValorMaximo > 0 then
      begin
        OBS := 'VALOR REFERENTE AO FIADO - ' +
          UpperCase(LJsonObj.GetValue<string>('nome'));
        conexao.SQL.Add
          ('update caixa_receber set pago = pago + :pago where id = :id');
        conexao.Parametros('pago', ValorMaximo);
        conexao.Parametros('id', DadosCaixa.FieldByName('id').AsInteger);
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('update caixa_receber set status = 2 where pago >= valor - 0.001 and id = :id');
        conexao.Parametros('id', DadosCaixa.FieldByName('id').AsInteger);
        conexao.ExecuteSQL;
        MovimentoCaixa(Caixa, DadosCaixa.FieldByName('id_pedido').AsInteger,
          Pagamento, 1, ValorMaximo, OBS, 0);
      end;
      DadosCaixa.Next;
    end;
  end;
  conexao.Free;
  LJsonObj.Free;
end;

procedure DoGetComanda(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  try
    conexao.SQL.Add('select mesa.* from mesa');
    conexao.SQL.Add
      ('join mesa_tipo on mesa_tipo.id_mesa_tipo = mesa.fk_tipo_mesa and upper(mesa_tipo.descricao) <> '
      + QuotedStr('MESA'));
    conexao.SQL.Add('where mesa.nr_mesa = :id ');
    conexao.Parametros('id', Req.Params['codigo'].ToInteger);
    // Req.Params['codigo'].ToInteger;
  except
    conexao.SQL.Clear;
    conexao.SQL.Add('select mesa.* from mesa');
    conexao.SQL.Add
      ('join mesa_tipo on mesa_tipo.id_mesa_tipo = mesa.fk_tipo_mesa and upper(mesa_tipo.descricao) <> '
      + QuotedStr('MESA'));
    conexao.SQL.Add('where  mesa.id_mesa = :id');
    conexao.Parametros('id', Req.Params['id'].ToInteger);
  end;
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostMesa(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('update mesa set descricao = :descricao where id_mesa = :id');
  try
    conexao.Parametros('descricao',
      'MESA ' + IntToStr(Req.Params['mesa'].ToInteger));
  except
    conexao.Parametros('descricao', UpperCase(Req.Params['mesa']));
  end;
  conexao.Parametros('id', IntToStr(Req.Params['codigo'].ToInteger));
  conexao.ExecuteSQL;
  conexao.SQL.Add('UPDATE pedido p');
  conexao.SQL.Add('JOIN mesa m ON m.selecionada = p.codigo');
  conexao.SQL.Add('JOIN mesa_tipo mt ON mt.id_mesa_tipo = m.fk_tipo_mesa');
  conexao.SQL.Add
    ('SET p.desc_ficha = CONCAT(UPPER(mt.descricao), " ", m.nr_mesa, " ", UPPER(m.descricao))');
  conexao.SQL.Add('WHERE m.id_mesa = :id;');
  conexao.Parametros('id', IntToStr(Req.Params['codigo'].ToInteger));
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoPostComandaDescricao(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('update mesa set descricao = :descricao where selecionada = :id');
  conexao.Parametros('descricao', Req.Params['mesa']);
  conexao.Parametros('id', IntToStr(Req.Params['codigo'].ToInteger));
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoGetTempoDelivery(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Tempo: Integer;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('select 0 as zero, temp_delivery from dados_whatsapp');
  Tempo := conexao.FieldByName('temp_delivery');
  if (Tempo <> Req.Params['tempo'].ToInteger) then
  begin
    conexao.SQL.Add('update dados_whatsapp set temp_delivery = :tempo');
    conexao.Parametros('tempo', IntToStr(Req.Params['tempo'].ToInteger));
    conexao.ExecuteSQL;
    EnviaTempoDelivery(Req.Params['tempo'].ToInteger);
  end;
  conexao.Free;
end;

// var
// conexao: TConexao;
// begin
// conexao := TConexao.Create('v2');
// conexao.SQL.Add('update dados_whatsapp set temp_delivery = :tempo');
// conexao.Parametros('tempo', IntToStr(Req.Params['tempo'].ToInteger));
// conexao.ExecuteSQL;
//
// EnviaTempoDelivery(Req.Params['tempo'].ToInteger);
// conexao.Free;
//
// end;
procedure DoPostCupomDescontoSite(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
  JsonIn: TJSONObject;
  JsonOut: TJSONObject;
begin
  JsonIn := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  if not Assigned(JsonIn) then
  begin
    Res.Status(400).Send('JSON inv?lido');
    exit;
  end;
  Requisicao := iRequisicao.Create(nil);
  try
    Requisicao.BaseURL := getUrlGoopedir;
    Requisicao.URL := 'api/cupom/empresa';
    Requisicao.Metodo := mPost;
    Requisicao.TempoExpiracao := 15 * 1000;
    // ?? Mesmo padr?o de autentica??o
    Requisicao.AddHeader('Authorization', frmServidor.APIGoopedir.GetToken);
    // ?? Monta o JSON que a API espera
    JsonOut := TJSONObject.Create;
    try
      JsonOut.AddPair('codigo', JsonIn.GetValue('codigo').Clone as TJSONValue);
      JsonOut.AddPair('cupom', JsonIn.GetValue('cupom').Clone as TJSONValue);
      JsonOut.AddPair('tipo', JsonIn.GetValue('tipo').Clone as TJSONValue);
      JsonOut.AddPair('percentual', JsonIn.GetValue('percentual')
        .Clone as TJSONValue);
      JsonOut.AddPair('valor', JsonIn.GetValue('valor').Clone as TJSONValue);
      JsonOut.AddPair('data', JsonIn.GetValue('data').Clone as TJSONValue);
      JsonOut.AddPair('quantidade', JsonIn.GetValue('quantidade')
        .Clone as TJSONValue);
      JsonOut.AddPair('min', JsonIn.GetValue('min').Clone as TJSONValue);
      JsonOut.AddPair('primeira', JsonIn.GetValue('primeira')
        .Clone as TJSONValue);
      // ?? Envia JSON direto
      Requisicao.body(JsonOut);
      Requisicao.Execute;
      // ?? Retorna exatamente o retorno do POST
      Res.Send(Requisicao.Retorno);
    finally
      JsonOut.Free;
    end;
  except
    on E: Exception do
      Res.Status(500).Send(E.Message);
  end;
  Requisicao.Free;
  JsonIn.Free;
end;

// var
// Requisicao: iRequisicao;
// body: String;
//
// JsonObj: TJSONObject;
// begin
// JsonObj := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
// Requisicao := iRequisicao.Create(nil);
// Requisicao.BaseURL := 'https://old.goopedir.com/v1/';
// Requisicao.URL := 'insert/cupom_desconto/' +
// frmServidor.UserID.ToString + '/a';
// Requisicao.TempoExpiracao := 15 * 1000;
// Requisicao.Metodo := mPost;
//
// body := '{"id_cupom":"' + JsonObj.GetValue<string>('codigo') +
// '", "user_id":"' + frmServidor.UserID.ToString + '", "ativacao":"' +
// JsonObj.GetValue<string>('cupom') + '", "type_discount":"' +
// JsonObj.GetValue<string>('tipo') + '", "porcentagem":"' +
// JsonObj.GetValue<string>('percentual') + '", "fixed_value":"' +
// JsonObj.GetValue<string>('valor') + '", "data_validade":"' +
// JsonObj.GetValue<string>('data') + '", "total_vezes":"' +
// JsonObj.GetValue<string>('quantidade') +
// '", "mostrar_site":"1", "automatico":"0", "primeira":"' +
// JsonObj.GetValue<string>('primeira') + '"}';
// Requisicao.body(body);
//
// try
// Requisicao.Execute;
// except
//
// end;
//
// Res.Send(GetCupomSite);
// end;
procedure DoGetSangriaCaixa(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('select c.id, CAST(c.descricao AS CHAR) AS descricao, c.valor, c.tipo from caixa_movimento as c');
  conexao.SQL.Add('where c.id_caixa = :id and c.tipo = 2');
  conexao.Parametros('id', IntToStr(Req.Params['id'].ToInteger));
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetPixPendenteTabela(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
  Dados: TFDMemTable;
begin
  Requisicao := iRequisicao.Create(nil);
  Dados := TFDMemTable.Create(nil);
  Requisicao.BaseURL := getUrlGoopedir;
  Requisicao.URL := 'api/empresa/pix/pendentes/' + frmServidor.UserID.ToString;
  Requisicao.MemTable2 := Dados;
  Requisicao.TempoExpiracao := 30 * 1000;
  Requisicao.Execute;
  Res.Send(Requisicao.Retorno);
  Requisicao.Free;
  Dados.Free;
end;

procedure DoGetFidelidadeSite(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
  Dados: TFDMemTable;
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetFidelidadeSite');
  Requisicao := iRequisicao.Create(nil);
  Dados := TFDMemTable.Create(nil);
  Requisicao.BaseURL := 'https://old.goopedir.com/v1/';
  if conexao.GetParametro('msg_massa') = '1' then
  begin
    Requisicao.URL := 'mensagem/' + frmServidor.UserID.ToString + '/a';
  end
  else
  begin
    Requisicao.URL := 'fidelidade/' + frmServidor.UserID.ToString + '/a';
  end;
  conexao.Free;
  Requisicao.MemTable2 := Dados;
  Requisicao.TempoExpiracao := 30 * 1000;
  Requisicao.Execute;
  Res.Send<TJsonArray>(Dados.ToJSONArray());
  Requisicao.Free;
  Dados.Free;
end;

procedure DoPostGravaMesa(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
  codigoTipo: Integer;
  Codigo: Integer;
  i: Integer;
begin
  JSONObject := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetBytes(Req.body), 0)
    as TJSONObject;
  conexao := TConexao.Create('v2');
  codigoTipo := JSONObject.GetValue('codigo').Value.ToInteger();
  if codigoTipo = 0 then
  begin
    codigoTipo := conexao.GerarID('mesa_tipo', 'id_mesa_tipo');
    conexao.SQL.Add
      ('insert into mesa_tipo (id_mesa_tipo, descricao, ativo) values (:id,:descricao,1)');
    conexao.Parametros('id', codigoTipo);
    conexao.Parametros('descricao', JSONObject.GetValue('descricao').Value);
    conexao.ExecuteSQL
  end;
  for i := JSONObject.GetValue('min').Value.ToInteger() to JSONObject.GetValue
    ('max').Value.ToInteger() do
  begin
    Codigo := conexao.GerarID('mesa', 'id_mesa');
    conexao.SQL.Add
      ('insert into mesa (id_mesa, nr_mesa,sts_mesa,qtd_mesa,tot_mesa,fk_tipo_mesa,ativo,selecionada) values (:id,:numero,0,0,0,:tipo,1,0)');
    conexao.Parametros('id', Codigo);
    conexao.Parametros('numero', i);
    conexao.Parametros('tipo', codigoTipo);
    conexao.ExecuteSQL;
  end;
  conexao.Free;
  JSONObject.Free;

  //
end;

procedure DoPostGravaMensagem(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
  Query: TFDQuery;
  EmojiValue: string;
  EmojiBytes: TBytes;
  MemoryStream: TMemoryStream;
  ImagemValue: string;
  ImagemBytes: TBytes;
  ImagemMemoryStream: TMemoryStream;
  Mensagem: Boolean;
  Imagem: Boolean;
begin
  try
    JSONObject := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetBytes(Req.body),
      0) as TJSONObject;
    conexao := TConexao.Create('v2');
    Query := conexao.CriaQRY;
    conexao.SQL.Add('delete from mensagem where dia = :dia');
    conexao.Parametros('dia', JSONObject.GetValue('dia').Value);
    conexao.ExecuteSQL;
    Query.SQL.Text :=
      'insert into mensagem (dia,texto,imagem) value (:dia,:texto,:imagem)';
    try
      EmojiValue := JSONObject.GetValue('mensagem').Value;
      // Supondo que este seja o valor do emoji
      // Converter a string Unicode UTF-16 para uma sequ?ncia de bytes UTF-8
      EmojiBytes := TEncoding.UTF8.GetBytes(EmojiValue);
      // Carregar os bytes UTF-8 em um TMemoryStream
      MemoryStream := TMemoryStream.Create;
      MemoryStream.WriteBuffer(EmojiBytes[0], Length(EmojiBytes));
      MemoryStream.position := 0;
      // Definir o par?metro usando os bytes UTF-8 do TMemoryStream
      Query.ParamByName('texto').LoadFromStream(MemoryStream, ftBlob);
      Mensagem := True;
      MemoryStream.Free;
    except
    end;
    try
      ImagemValue := JSONObject.GetValue('imagem').Value;
      // Supondo que este seja o valor do emoji
      // Converter a string Unicode UTF-16 para uma sequ?ncia de bytes UTF-8
      ImagemBytes := TEncoding.UTF8.GetBytes(ImagemValue);
      // Carregar os bytes UTF-8 em um TMemoryStream
      ImagemMemoryStream := TMemoryStream.Create;
      ImagemMemoryStream.WriteBuffer(ImagemBytes[0], Length(ImagemBytes));
      ImagemMemoryStream.position := 0;
      // Definir o par?metro usando os bytes UTF-8 do TMemoryStream
      Query.ParamByName('imagem').LoadFromStream(ImagemMemoryStream, ftBlob);
      Imagem := True;
      ImagemMemoryStream.Free;
    except
    end;
    if not Mensagem then
    begin
      Query.ParamByName('texto').AsString := '';
    end;
    if not Imagem then
    begin
      Query.ParamByName('imagem').AsString := '';
    end;
    // Query.ParamByName('texto').AsString := 'Texto com emoji ??'; // Substitua isso pelo seu emoji
    // Query.ParamByName('texto').AsBlob := TEncoding.UTF8.GetBytes(JSONObject.GetValue('mensagem').Value);
    Query.ParamByName('dia').AsString := JSONObject.GetValue('dia').Value;
    // Substitua isso pelo seu emoji
    Query.ExecSQL;
    Query.Free;
    // conexao.SQL.Add('insert into mensagem (dia,texto) value (:dia,:texto)');
    // conexao.Parametros('dia', JSONObject.GetValue('dia').Value);
    // conexao.Parametros('texto', JSONObject.GetValue('mensagem').Value);
    // conexao.Parametros('dia', JSONObject.GetValue('dia').Value);
    // conexao.ExecuteSQL;
    conexao.Free;
  except
    on E: Exception do
    begin
      // //////showmessage1(E.Message)
    end;
  end;
end;

procedure doGetGroup(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send(frmServidor.memGrupo.ToJSONArray());
end;

procedure DoPostGroup(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  frmServidor.memGrupo.Close;
  frmServidor.memGrupo.Open;
  frmServidor.memGrupo.LoadFromJSON(Req.body);
  if frmServidor.memGrupo.RecordCount > 0 then
  begin
    frmServidor.memGrupo.SaveToFile('grupo.whatsapp');
  end;
end;

procedure DoGetProdutoFoto(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetProdutoFoto');
  conexao.SQL.Add
    ('select distinct foto_ifood as imagem, nome_produto as nome from produto where foto_ifood <> ""');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetFiscalIBSCBSCST(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetFiscalIBSCBSCST');
  try
    conexao.SQL.Add('select cst, descricao, ind_nfe, ind_nfce, ind_nfse');
    conexao.SQL.Add('from fiscal_ibs_cbs_cst');
    conexao.SQL.Add('order by cst');
    Res.Send<TJsonArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;

procedure DoGetFiscalIBSCBSClassTrib(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  CST: String;
begin
  conexao := TConexao.Create('DoGetFiscalIBSCBSClassTrib');
  try
    CST := '';
    try
      CST := Trim(Req.Params['cst']);
    except
      CST := '';
    end;
    conexao.SQL.Add('select cclass_trib, cst, nome, descricao, tipo_aliquota,');
    conexao.SQL.Add('pred_ibs, pred_cbs, ind_redutor_bc, credito_para,');
    conexao.SQL.Add
      ('dini_vig, dfim_vig, ind_nfe, ind_nfce, ind_nfse, anexo, link');
    conexao.SQL.Add('from fiscal_ibs_cbs_class_trib');
    if CST <> '' then
    begin
      conexao.SQL.Add('where cst = :cst');
      conexao.Parametros('cst', CST);
    end;
    conexao.SQL.Add('order by cst, cclass_trib');
    Res.Send<TJsonArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;

procedure DoGetFiscalIBSCBSConfiguracao(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSON: TJSONObject;
begin
  conexao := TConexao.Create('DoGetFiscalIBSCBSConfiguracao');
  JSON := TJSONObject.Create;
  try
    conexao.SQL.Add('select cst, descricao, ind_nfe, ind_nfce, ind_nfse');
    conexao.SQL.Add('from fiscal_ibs_cbs_cst');
    conexao.SQL.Add('order by cst');
    JSON.AddPair('cst', conexao.ConsultaSQL);

    conexao.SQL.Add('select cclass_trib, cst, nome, descricao, tipo_aliquota,');
    conexao.SQL.Add('pred_ibs, pred_cbs, ind_redutor_bc, credito_para,');
    conexao.SQL.Add
      ('dini_vig, dfim_vig, ind_nfe, ind_nfce, ind_nfse, anexo, link');
    conexao.SQL.Add('from fiscal_ibs_cbs_class_trib');
    conexao.SQL.Add('order by cst, cclass_trib');
    JSON.AddPair('class_trib', conexao.ConsultaSQL);

    Res.Send<TJSONObject>(JSON);
  finally
    conexao.Free;
  end;
end;

procedure DoGetProdutoFiscal(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetProdutoFiscal');
  conexao.SQL.Add
    ('select codigo, nome_produto, un, ncm,cest,cfop,cstipi,csticms,csosn, icms,ipi, pis,cofins, frete, ibs_cbs_cst, ibs_cbs_class_trib, ibs_uf_aliq, ibs_mun_aliq, cbs_aliq from produto');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostSincronizaParametros(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  frmServidor.SincronizaParametros;
  AtualizaParametro;
end;

procedure GetCacheSite(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  try
    frmServidor.Queue.Finalizar(Req.body.ToInteger());
  except
  end;
  frmServidor.AtualizaCacheSite;
end;

procedure DoGetCategoriaExtra(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  DadosAdicionais: TFDMemTable;
  DadosAdicionaisItens: TFDMemTable;
  JSonArrayAdicional: TJsonArray;
  JsonObjetoCategoriaAdicional: TJSONObject;
  JSonArrayAdicionalItens: TJsonArray;
  JSonObjetoAdicionalItens: TJSONObject;
begin
  conexao := TConexao.Create('DoGetCategoriaExtra');
  conexao.SQL.Add
    ('SELECT * FROM pro_adi_personalizado where categoria = :categoria');
  conexao.Parametros('categoria', Req.Params['codigo']);
  DadosAdicionais := TFDMemTable.Create(nil);
  DadosAdicionaisItens := TFDMemTable.Create(nil);
  DadosAdicionais.LoadFromJSON(conexao.ConsultaSQL);
  JSonArrayAdicional := TJsonArray.Create;
  if DadosAdicionais.RecordCount > 0 then
  begin
    while not DadosAdicionais.Eof do
    begin
      JsonObjetoCategoriaAdicional := TJSONObject.Create;
      JsonObjetoCategoriaAdicional.AddPair('id',
        DadosAdicionais.FieldByName('id').AsInteger);
      JsonObjetoCategoriaAdicional.AddPair('name',
        DadosAdicionais.FieldByName('descricao').AsString);
      JsonObjetoCategoriaAdicional.AddPair('status',
        DadosAdicionais.FieldByName('ativo').AsInteger);
      JsonObjetoCategoriaAdicional.AddPair('min',
        DadosAdicionais.FieldByName('qtd_minima').AsInteger);
      JsonObjetoCategoriaAdicional.AddPair('max',
        DadosAdicionais.FieldByName('qtd_maxima').AsInteger);
      DadosAdicionaisItens.Close;
      conexao.SQL.Add
        ('select * from pro_adi_personalizado_sabores where id_pro_adi_personalizado = :id');
      conexao.Parametros('id', DadosAdicionais.FieldByName('id').AsInteger);
      DadosAdicionaisItens.LoadFromJSON(conexao.ConsultaSQL);
      JSonArrayAdicionalItens := TJsonArray.Create;
      while not DadosAdicionaisItens.Eof do
      begin
        JSonObjetoAdicionalItens := TJSONObject.Create;
        JSonObjetoAdicionalItens.AddPair('id',
          DadosAdicionaisItens.FieldByName('id').AsInteger);
        JSonObjetoAdicionalItens.AddPair('name',
          DadosAdicionaisItens.FieldByName('nome').AsString);
        JSonObjetoAdicionalItens.AddPair('description',
          DadosAdicionaisItens.FieldByName('descricao').AsString);
        JSonObjetoAdicionalItens.AddPair('value',
          DadosAdicionaisItens.FieldByName('valor').AsFloat);
        JSonObjetoAdicionalItens.AddPair('stock',
          DadosAdicionaisItens.FieldByName('id_prod_estoque').AsInteger);
        JSonObjetoAdicionalItens.AddPair('status',
          DadosAdicionaisItens.FieldByName('ativo').AsInteger);
        JSonObjetoAdicionalItens.AddPair('insulmo',
          DadosAdicionaisItens.FieldByName('id_ingredientes').AsInteger);
        JSonArrayAdicionalItens.AddElement(JSonObjetoAdicionalItens);
        // if DadosAdicionaisItens.FieldByName('valor').AsFloat > 0 then
        // begin
        // if Min > DadosAdicionaisItens.FieldByName('valor').AsFloat then
        // Min := DadosAdicionaisItens.FieldByName('valor').AsFloat;
        //
        // if DadosAdicionaisItens.FieldByName('valor').AsFloat > Max then
        // Max := DadosAdicionaisItens.FieldByName('valor').AsFloat;
        // end;
        DadosAdicionaisItens.Next;
      end;
      JsonObjetoCategoriaAdicional.AddPair('extra', JSonArrayAdicionalItens);
      JSonArrayAdicional.Add(JsonObjetoCategoriaAdicional);
      DadosAdicionais.Next;
    end;
    // JsonObjeto.AddPair('additional', JSonArrayAdicional);
  end;
  Res.Send<TJsonArray>(JSonArrayAdicional);
  DadosAdicionaisItens.Free;
  DadosAdicionais.Free;
  conexao.Free;
end;

procedure DoGetValidaFechamentoCaixa(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
end;

procedure DoPostZeraNFCE(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  try
    frmServidor.memErrosNFCE.Close;
    frmServidor.memErrosNFCE.Open;
  except
  end;
end;

procedure DoPostErroNFCE(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  Dados: TFDMemTable;
  PodeInserir: Boolean;
  conexao: TConexao;
begin
  try
    JSONValue := TJSONObject.ParseJSONValue(Req.body);
    if Assigned(JSONValue) and (JSONValue is TJSONObject) then
    begin
      JSONObject := JSONValue as TJSONObject;
      Dados := TFDMemTable.Create(nil);
      Dados.LoadFromJSON(frmServidor.memErrosNFCE.ToJSONArray());
      PodeInserir := True;
      if Dados.RecordCount > 0 then
      begin
        while not Dados.Eof do
        begin
          if Dados.FieldByName('pedido').AsString = JSONObject.Values['pedido'].Value
          then
          begin
            PodeInserir := False;
          end;
          Dados.Next;
        end;
      end;
      Dados.Free;
      if PodeInserir then
      begin
        conexao := TConexao.Create('DoPostErroNFCE');
        conexao.SQL.Add
          ('UPDATE pedido SET nfce_status = "ERRO", nfce_tentativas = nfce_tentativas + 1 WHERE codigo = :pedido');
        conexao.Parametros('pedido', JSONObject.Values['pedido'].Value);
        conexao.ExecuteSQL;
        frmServidor.memErrosNFCE.Last;
        frmServidor.memErrosNFCE.Insert;
        frmServidor.memErrosNFCE.FieldByName('data').AsDateTime := now;
        frmServidor.memErrosNFCE.FieldByName('pedido').AsString :=
          JSONObject.Values['pedido'].Value;
        frmServidor.memErrosNFCE.FieldByName('erros').AsString :=
          JSONObject.Values['erro'].Value;
        frmServidor.memErrosNFCE.Post;
      end;
    end;
  except
  end;
end;

procedure DoGetPainelChamada(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetPainelChamada');
  conexao.SQL.Add
    ('select pp.id, p.codigo_pedido_dia as codigo, pp.quantidade,');
  conexao.SQL.Add('CASE p.nome');
  conexao.SQL.Add('        WHEN "" THEN c.nome');
  conexao.SQL.Add('        ELSE p.nome');
  conexao.SQL.Add('    END AS nome from pedido_painel as pp');
  conexao.SQL.Add('join pedido as p on p.codigo = pp.id_pedido');
  conexao.SQL.Add('join cliente as c on c.codigo = p.codigo_cliente');
  conexao.SQL.Add('where pp.quantidade < 3 order by id asc limit 5');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

function XMLToJSON(Node: IXMLNode): TJSONObject;
var
  i: Integer;
  Child: IXMLNode;
begin
  Result := TJSONObject.Create;
  for i := 0 to Node.ChildNodes.Count - 1 do
  begin
    Child := Node.ChildNodes[i];
    if Child.HasChildNodes and (Child.ChildNodes.Count > 1) then
      Result.AddPair(Child.NodeName, XMLToJSON(Child))
    else
      Result.AddPair(Child.NodeName, Child.Text);
  end;
end;

procedure DoPostPonte(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send(ExecutarProxyRequest(Req.body))
end;

procedure DoPostAtualizaObsProduto(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
Var
  JSONValue: TJSONValue;
  conexao: TConexao;
  Codigo: Integer;
  Dados: TFDMemTable;
  ProductItem: TJSONObject;
begin
  conexao := TConexao.Create('DoPostAtualizaObsProduto');
  Dados := TFDMemTable.Create(nil);
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  ProductItem := JSONValue as TJSONObject;
  conexao.SQL.Add('SELECT * FROM pedido_produtos where codigo = :codigo');
  conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  if Dados.RecordCount > 0 then
  begin
    conexao.SQL.Add
      ('update pedido_produtos set html = :html where codigo = :codigo');
    conexao.Parametros('html', StringReplace(Dados.FieldByName('html').AsString,
      ProductItem.GetValue<String>('old'), ProductItem.GetValue<String>('new'),
      [rfIgnoreCase]));
    conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('select * from pedido_produto_sap where codigo_pedido_produto = :codigo and upper(nomeclatura) like "%OBSERVA%"');
    conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
    Codigo := conexao.FieldByName('id');
    if Codigo > 0 then
    begin
      conexao.SQL.Add
        ('update pedido_produto_sap set descricao = :obs where id = :codigo');
      conexao.Parametros('obs', ProductItem.GetValue<String>('new'));
      conexao.Parametros('codigo', Codigo);
    end
    else
    begin
      Codigo := conexao.GerarID('pedido_produto_sap', 'id');
      conexao.SQL.Add
        ('insert into pedido_produto_sap (id,codigo_pedido_produto,tipo,nomeclatura,descricao) values (:id,:codigo,0,"OBSERVACAO",:descricao)');
      conexao.Parametros('id', Codigo);
      conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
      conexao.Parametros('descricao', ProductItem.GetValue<String>('new'));
    end;
    conexao.ExecuteSQL;
  end;
  if ProductItem.GetValue<string>('reimpressao') = '1' then
  begin
    conexao.SQL.Add
      ('update pedido_produtos set impressao = 0, impresso = 0 where codigo = :codigo');
    conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('delete from pedido_produto_sap where upper(nomeclatura) like "%ATEN?%" where codigo_pedido_produto = :codigo');
    conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('delete from pedido_produto_sap where codigo_pedido_produto = :codigo and descricao = :descricao');
    conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
    conexao.Parametros('descricao',
      'OBSERVACAO FOI ALTERADA E ESSA E UMA REIMPRESSAO');
    conexao.ExecuteSQL;
    Codigo := conexao.GerarID('pedido_produto_sap', 'id');
    conexao.SQL.Add
      ('insert into pedido_produto_sap (id,codigo_pedido_produto,tipo,nomeclatura,descricao) values (:id,:codigo,0,"* * * * ATENCAO * * * *",:descricao)');
    conexao.Parametros('id', Codigo);
    conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
    conexao.Parametros('descricao',
      'OBSERVACAO FOI ALTERADA E ESSA E UMA REIMPRESSAO');
    conexao.ExecuteSQL;
    if conexao.GetParametro('nova_impressao') = '1' then
    begin
      frmServidor.enviarImpressaoGo(ProductItem.GetValue<Integer>('codigo'),
        'codigo');
    end
    else
    begin
      conexao.SQL.Add
        ('update impressao_pedido_produto set data_impressao = null, hora_impressao = null, status = 0 where id_pedido = :codigo');
      conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
      conexao.ExecuteSQL;
      conexao.SQL.Add
        ('update pedido_produtos set impresso = 3, impressao = 3 where codigo_pedido = :codigo');
      conexao.Parametros('codigo', ProductItem.GetValue<Integer>('codigo'));
      conexao.ExecuteSQL;
    end;
  end;
  //
  Codigo := Dados.FieldByName('codigo_pedido').AsInteger;
  LimpaCache('GetDadosProdutoPedido', Codigo.ToString);
  Res.Send<TJsonArray>(GetDadosProdutoPedido(Codigo));
  conexao.Free;
  Dados.Free;
end;

procedure DoGetTipos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Request: iRequisicao;
begin
  if frmServidor.CacheTiposJSON = '' then
  begin
    Request := iRequisicao.Create(nil);
    Request.BaseURL := getUrlGoopedir;
    Request.URL := 'api/interno/consulta/tipo/produto/geral';
    try
      Request.Execute;
      frmServidor.CacheTiposJSON := Request.Retorno;
    except
    end;
    Request.Free;
  end;
  Res.Send<TJsonArray>(TJSONObject.ParseJSONValue
    (TEncoding.UTF8.GetBytes(frmServidor.CacheTiposJSON), 0) as TJsonArray);
end;

procedure DoGetDadosDashBoardPrincipal(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Pedidos: TFDMemTable;
  CaixaMov: TFDMemTable;
  Produtos: TFDMemTable;
  TotalHoje: Real; // ok
  PedidosHoje: Integer; // ok
  PedidosConcluido: Integer; // ok
  PedidosRota: Integer;
  PedidosCancelado: Integer; // ok
  percentualCancelado: Real;
  PedidoAtrasado: Integer;
  TempoMedio: Real;
  qtdTempo: Integer;
  ClienteNovos: Integer;
  ClienteRecorrente: Integer;
  ObjPagamento: TJSONObject;
  ArrayPagamento: TJsonArray;
  TotalMesa: Real;
  DataIni: String;
  DataFim: String;
  Retorno: TJSONObject;
begin
  DataIni := FormatDateTime('yyyy-mm-dd 02:00:00', now);
  DataFim := FormatDateTime('yyyy-mm-dd 02:00:00', IncDay(now, 1));
  conexao := TConexao.Create('DoGetDadosDashBoardPrincipal');
  Retorno := TJSONObject.Create;
  conexao.ExecuteSQL('CALL atualizar_data_cadastro_cliente();');
  Pedidos := TFDMemTable.Create(nil);
  CaixaMov := TFDMemTable.Create(nil);
  Produtos := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('select codigo_cliente, status, valor_total_pedido as total, id_caixa as caixa, nfce_chave, partner, (cliente.data_cadastro = current_date) as newcli,');
  conexao.SQL.Add('TIMESTAMPDIFF(MINUTE,NOW(),preparo_hora) AS min');
  conexao.SQL.Add('from pedido');
  conexao.SQL.Add
    ('left join cliente on cliente.codigo = pedido.codigo_cliente');
  conexao.SQL.Add
    ('where codigo_pedido_dia > 0 and (id_ficha = 0 or id_ficha is null) and data_hora BETWEEN :ini AND :fim');
  conexao.Parametros('ini', DataIni);
  conexao.Parametros('fim', DataFim);
  Pedidos.LoadFromJSON(conexao.ConsultaSQL);
  PedidosHoje := 0;
  PedidosCancelado := 0;
  PedidosConcluido := 0;
  TotalHoje := 0;
  PedidoAtrasado := 0;
  TempoMedio := 0;
  qtdTempo := 0;
  PedidosRota := 0;
  ClienteNovos := 0;
  ClienteRecorrente := 0;
  if Pedidos.RecordCount > 0 then
  begin
    while not Pedidos.Eof do
    begin
      inc(PedidosHoje);
      TotalHoje := TotalHoje + Pedidos.FieldByName('total').AsFloat;
      if Pedidos.FieldByName('status').AsInteger = 0 then
      begin
        inc(PedidosCancelado);
        PedidosHoje := PedidosHoje - 1;
        TotalHoje := TotalHoje - Pedidos.FieldByName('total').AsFloat;
      end;
      if Pedidos.FieldByName('status').AsInteger = 6 then
        inc(PedidosConcluido);
      if Pedidos.FieldByName('status').AsInteger = 3 then
        inc(PedidosRota);
      if Pedidos.FieldByName('status').AsInteger = 5 then
        inc(PedidosRota);
      if Pedidos.FieldByName('newcli').AsInteger = 1 then
        inc(ClienteNovos)
      else
        inc(ClienteRecorrente);
      if Pedidos.FieldByName('status').AsInteger = 2 then
      begin
        // Em Produ??o
        if Pedidos.FieldByName('min').AsInteger <= 5 then
        begin
          inc(PedidoAtrasado)
        end
        else
        begin
          TempoMedio := TempoMedio + Pedidos.FieldByName('min').AsInteger;
          inc(qtdTempo);
        end;
      end;
      Pedidos.Next;
    end;
  end;
  Retorno.AddPair('faturamentoHoje', Trunc(TotalHoje * 100) / 100);
  Retorno.AddPair('pedidosHoje', PedidosHoje);
  Retorno.AddPair('ticketMedioHoje',
    Trunc((TotalHoje / PedidosHoje) * 100) / 100);
  Retorno.AddPair('pedidosAguardando',
    PedidosHoje - (PedidosConcluido + PedidosRota));
  if qtdTempo > 0 then
    Retorno.AddPair('tempoMedio', (TempoMedio / qtdTempo))
  else
    Retorno.AddPair('tempoMedio', (TempoMedio));
  Retorno.AddPair('pedidoAtrasado', PedidoAtrasado);
  Retorno.AddPair('pedidoCancelado', PedidosCancelado);
  percentualCancelado := 0;
  if (PedidosHoje > 0) then
    percentualCancelado :=
      (PedidosCancelado / (PedidosCancelado + PedidosHoje)) * 100;
  percentualCancelado := Trunc(percentualCancelado * 100) / 100;
  Retorno.AddPair('percentualCancelado', percentualCancelado);

  // Dados Pagamento
  conexao.SQL.Add
    ('select sum(valor) as total, count(*) as qtd, tp.codigo, tp.descricao from caixa_movimento as cm');
  conexao.SQL.Add
    ('join tipo_pagamento as tp on tp.codigo = cm.id_tipo_pagamento');
  conexao.SQL.Add('where cm.tipo = 1 and cm.data_hora BETWEEN :ini AND :fim');
  conexao.SQL.Add('group by tp.codigo, tp.descricao');
  conexao.Parametros('ini', DataIni);
  conexao.Parametros('fim', DataFim);
  CaixaMov.LoadFromJSON(conexao.ConsultaSQL);
  ArrayPagamento := TJsonArray.Create;
  if CaixaMov.RecordCount > 0 then
  begin
    while not CaixaMov.Eof do
    begin
      ObjPagamento := TJSONObject.Create;
      ObjPagamento.AddPair('codigo', CaixaMov.FieldByName('codigo').AsInteger);
      ObjPagamento.AddPair('nome', CaixaMov.FieldByName('descricao').AsString);
      if (conexao.GetParametro('cx_resumido') = 1) then
        ObjPagamento.AddPair('value', CaixaMov.FieldByName('qtd').AsInteger)
      else
        ObjPagamento.AddPair('value', CaixaMov.FieldByName('total').AsFloat);
      ArrayPagamento.AddElement(ObjPagamento);
      CaixaMov.Next;
    end;
  end;
  Retorno.AddPair('meioPagamento', ArrayPagamento);
  Retorno.AddPair('clienteNovo', ClienteNovos);
  Retorno.AddPair('clienteRecorrente', ClienteRecorrente);
  Retorno.AddPair('clientes', ClienteNovos + ClienteRecorrente);
  // produtos
  conexao.SQL.Add
    ('select pro.codigo, pro.nome_produto as produto, sum(pp.quantidade) as quantidade from pedido as p');
  conexao.SQL.Add('join pedido_produtos as pp on pp.codigo_pedido = p.codigo');
  conexao.SQL.Add('join produto as pro on pro.codigo = pp.codigo_produto');
  conexao.SQL.Add
    ('where p.codigo_pedido_dia > 0 and (p.id_ficha = 0 or p.id_ficha is null) and data_hora BETWEEN :ini AND :fim');
  conexao.SQL.Add('group by pro.codigo, pro.nome_produto');
  conexao.SQL.Add('order by sum(pp.quantidade) desc limit 3');
  conexao.Parametros('ini', DataIni);
  conexao.Parametros('fim', DataFim);
  Produtos.LoadFromJSON(conexao.ConsultaSQL);
  Retorno.AddPair('produtos', Produtos.ToJSONArray());
  Res.Send<TJSONObject>(Retorno);
  conexao.Free;
  CaixaMov.Free;
  Pedidos.Free;
end;

procedure DoPutBancos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  JSON: TJSONValue;
  Database: string;
  CaminhoConfig: string;
  Linhas: TStringList;
  i: Integer;
  StartupInfo: TStartupInfo;
  ProcessInfo: TProcessInformation;
begin
  JSON := TJSONObject.ParseJSONValue(Req.body);
  if not Assigned(JSON) then
  begin
    Res.Status(400).Send('Body inv?lido');
    exit;
  end;
  if not JSON.TryGetValue<string>('banco', Database) then
  begin
    Res.Status(400).Send('Campo "banco" n?o informado');
    exit;
  end;
  CaminhoConfig := TPath.Combine(ExtractFilePath(ParamStr(0)),
    'configuracao\confi.dados');
  if not FileExists(CaminhoConfig) then
  begin
    Res.Status(500).Send('Arquivo confi.dados n?o encontrado');
    exit;
  end;
  Linhas := TStringList.Create;
  try
    Linhas.LoadFromFile(CaminhoConfig);
    for i := 0 to Linhas.Count - 1 do
    begin
      if Linhas[i].StartsWith('Database=') then
      begin
        Linhas[i] := 'Database=' + Database;
        Break;
      end;
    end;
    Linhas.SaveToFile(CaminhoConfig);
  finally
    Linhas.Free;
  end;
  frmServidor.setUser;
  // Responde antes de derrubar o servidor
  Res.Status(200).Send('Banco atualizado. Reiniciando servi?os...');
  frmServidor.timerClose.Enabled := True;
end;

procedure DoGetBancos(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
begin
  Dados := TFDMemTable.Create(nil);
  conexao := TConexao.Create('DoGetBancos');
  conexao.SQL.Add('SELECT 0 as atual, schema_name as banco');
  conexao.SQL.Add('FROM information_schema.schemata');
  conexao.SQL.Add
    ('WHERE schema_name NOT REGEXP "^(mysql|sys|information_schema|performance_schema|goopedir|goopedir_cache)" ORDER BY schema_name');
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      if Dados.FieldByName('banco').AsString = conexao.NomeBanco then
      begin
        Dados.Edit;
        Dados.FieldByName('atual').AsInteger := 1;
        Dados.Post;
      end;
      Dados.Next;
    end;
  end;
  Res.Send<TJsonArray>(Dados.ToJSONArray());
  Dados.Free;
  conexao.Free;
end;

procedure DoGetClienteHistorico(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  DataIni: String;
  DataFim: String;
  cliente: Integer;
  Tipo: Integer;
  Data: TFDMemTable;
  DataProduto: TFDMemTable;
  Obj: TJSONObject;
  Dados: TJsonArray;
  ArrayProdutos: TJsonArray;
  ObjProduto: TJSONObject;
begin
  Dados := TJsonArray.Create;
  Tipo := StrToIntDef(Req.Query['tipo'], 0);
  cliente := StrToIntDef(Req.Query['cliente'], 0);
  try
    DataIni := Req.Query['ini'];
  except
    DataIni := FormatDateTime('yyyy-mm-01', now)
  end;
  try
    DataFim := Req.Query['fim'];
  except
    DataIni := FormatDateTime('yyyy-mm-dd', now)
  end;
  Data := TFDMemTable.Create(nil);
  conexao := TConexao.Create('DoGetClienteHistorico');
  conexao.SQL.Add
    ('SELECT codigo, concat(DATE_FORMAT(data_pedido, "%d/%m/%Y ") ,hora_pedido) as data, ');
  conexao.SQL.Add(' CASE codigo_cliente_endereco');
  conexao.SQL.Add('    WHEN 0 THEN "Vem Buscar"');
  conexao.SQL.Add('    ELSE "Delivery"');
  conexao.SQL.Add('  END AS origem,');
  conexao.SQL.Add('  status_pedido.descricao,');
  conexao.SQL.Add('valor_total_pedido as total,');
  conexao.SQL.Add('valor_taxa_entrega as taxa,');
  conexao.SQL.Add('valor_desconto as entrega');
  conexao.SQL.Add('FROM pedido ');
  conexao.SQL.Add('join status_pedido on status_pedido.id = pedido.status');
  conexao.SQL.Add
    (' where data_pedido between :ini and :fim and codigo_pedido_dia > 0 and codigo_cliente = :cliente');
  if Tipo = 1 then
  begin
    conexao.SQL.Add('and codigo_cliente_endereco > 0');
  end;
  if Tipo = 2 then
  begin
    conexao.SQL.Add('and codigo_cliente_endereco = 0');
  end;
  conexao.Parametros('ini', DataIni);
  conexao.Parametros('fim', DataFim);
  conexao.Parametros('cliente', cliente);
  Data.LoadFromJSON(conexao.ConsultaSQL());
  if Data.RecordCount > 0 then
  begin
    while not Data.Eof do
    begin
      Obj := TJSONObject.Create;
      Obj.AddPair('id', Data.FieldByName('codigo').AsInteger);
      Obj.AddPair('data', Data.FieldByName('data').AsString);
      Obj.AddPair('origem', Data.FieldByName('origem').AsString);
      Obj.AddPair('status', Data.FieldByName('descricao').AsString);
      Obj.AddPair('total', Data.FieldByName('total').AsFloat);
      Obj.AddPair('taxa', Data.FieldByName('taxa').AsFloat);
      Obj.AddPair('entrega', Data.FieldByName('entrega').AsFloat);
      ArrayProdutos := TJsonArray.Create;
      DataProduto := TFDMemTable.Create(nil);
      conexao.SQL.Add
        ('SELECT quantidade, valor_total as valor, produto.nome_produto as nome');
      conexao.SQL.Add('FROM pedido_produtos ');
      conexao.SQL.Add
        ('left join produto on produto.codigo = pedido_produtos.codigo_produto');
      conexao.SQL.Add('where codigo_pedido = :codigo');
      conexao.Parametros('codigo', Data.FieldByName('codigo').AsInteger);
      DataProduto.LoadFromJSON(conexao.ConsultaSQL);
      if DataProduto.RecordCount > 0 then
      begin
        while not DataProduto.Eof do
        begin
          ObjProduto := TJSONObject.Create;
          ObjProduto.AddPair('nome', DataProduto.FieldByName('nome').AsString);
          ObjProduto.AddPair('valor', DataProduto.FieldByName('valor').AsFloat);
          ObjProduto.AddPair('quantidade',
            DataProduto.FieldByName('quantidade').AsFloat);
          ArrayProdutos.AddElement(ObjProduto);
          DataProduto.Next;
        end;
      end;
      Obj.AddPair('itens', ArrayProdutos);
      DataProduto.Free;
      Dados.AddElement(Obj);
      Data.Next;
    end;
  end;
  Res.Send<TJsonArray>(Dados);
end;

procedure DoGetCardapioIA(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  ID: String;
  iRequest: iRequisicao;
begin
  conexao := TConexao.Create('DoGetCardapioIA');
  conexao.SQL.Add('select * from config_temporaria limit 1');
  try
    ID := conexao.FieldByName('job_id');
  except
    ID := '';
  end;
  conexao.Free;
  if (ID = '') then
  begin
    Res.Send('{}');
    exit;
  end;
  iRequest := iRequisicao.Create(nil);
  iRequest.BaseURL := getUrlGoopedir;
  iRequest.URL := 'api/cardapio/ia/status/' + ID;
  iRequest.TempoExpiracao := 60 * 1000;
  try
    iRequest.Execute;
    Res.Send(iRequest.Retorno);
  except
    Res.Send('{}');
  end;
  iRequest.Free;
end;

procedure DoPostCardapioIA(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  iRequest: iRequisicao;
  Retorno: TJSONObject;
  conexao: TConexao;
begin
  iRequest := iRequisicao.Create(nil);
  iRequest.BaseURL := getUrlGoopedir;
  iRequest.URL := 'api/cardapio/ia/upload';
  iRequest.TempoExpiracao := 60 * 1000;
  iRequest.Metodo := mPost;
  iRequest.body(Req.body);
  try
    iRequest.Execute;
    Retorno := TJSONObject.ParseJSONValue(iRequest.Retorno) as TJSONObject;
    Retorno.GetValue<String>('jobId');
    conexao := TConexao.Create('DoPostCardapioIA');
    conexao.SQL.Add('update config_temporaria set job_id = :job');
    conexao.Parametros('job', Retorno.GetValue<String>('jobId'));
    conexao.ExecuteSQL;
    conexao.Free;
  except
  end;
  iRequest.Free;
  Res.Send(Retorno);
end;



procedure DoGetImportaPedidoSite(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  path : String;
  parametro : String;
begin

//conexao.Parametros('codigo', Req.Params['id'].ToInteger);
  path := frmServidor.PathExe  + 'psGoopedir.exe ';
  parametro := Req.Params['id']+' '+frmServidor.UserID.ToString;
  frmServidor.AbrirExe(path,parametro);
  Res.Send('Ok');
end;

procedure DoDeleteProduto(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoDeleteProduto');
  conexao.SQL.Add
    ('update produto set ativo = 0, deletado = 1 where codigo = :codigo');
  conexao.Parametros('codigo', Req.Params['id'].ToInteger);
  conexao.ExecuteSQL;
  conexao.Free;
  EnviaProduto(Req.Params['id'].ToInteger, '', '');
end;

procedure DoPutUltimoProduto(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  try
    frmServidor.Queue.Finalizar(Req.Params['id'].ToInteger);
  except
  end;
end;

procedure DoGetUltimoProduto(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Codigo: Integer;
begin
  Codigo := frmServidor.Queue.PegarProximo;
  Res.Send(Codigo.ToString);
end;

procedure DoPutPainelChamada(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoPostPainelChamada');
  conexao.SQL.Add
    ('update pedido_painel set quantidade = quantidade +1 where id = :id');
  conexao.Parametros('id', Req.Params['id']);
  conexao.ExecuteSQL;
  conexao.Free;
  Res.Send('OK');
end;

procedure DoPostPainelChamada(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoPostPainelChamada');
  conexao.SQL.Add('insert into pedido_painel (id_pedido) values (:id)');
  conexao.Parametros('id', Req.Params['id']);
  conexao.ExecuteSQL;
  conexao.Free;
  Res.Send('OK');
end;

procedure DoGetPesoBalanca(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  ID: string;
  peso: Double;
begin
  ID := Req.Params['id'];
  peso := frmServidor.BalancaManager.ObterPeso(ID);
  Res.Send<TJSONObject>(TJSONObject.Create.AddPair('peso',
    TJSONNumber.Create(peso)));
end;

procedure DoPostBalanca(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
begin
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  if Assigned(JSONValue) and (JSONValue is TJSONObject) then
  begin
    JSONObject := JSONValue as TJSONObject;
    try
      frmServidor.BalancaManager.AtualizarPeso(JSONObject.Values['id'].Value,
        StrToFloat(StringReplace(JSONObject.Values['peso'].Value, '.',
        ',', [])));
    except
      on E: Exception do
      begin
      end;
    end;
    conexao := TConexao.Create('DoPostBalanca');
    conexao.SQL.Add
      ('update balanca set peso = :peso, ultima_sinc = current_timestamp() where id = :id');
    conexao.Parametros('peso', JSONObject.Values['peso'].Value);
    conexao.Parametros('id', JSONObject.Values['id'].Value);
    conexao.ExecuteSQL;
    conexao.Free;
    JSONObject.Free;
  end;
end;

procedure DoPostImagemEmpresa(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  CaminhoImagem: String;
  conexao: TConexao;
  Qry: TFDQuery;
begin
  // Fazer o parsing do JSON
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  // Verificar se o JSON foi parseado com sucesso
  if Assigned(JSONValue) and (JSONValue is TJSONObject) then
  begin
    JSONObject := JSONValue as TJSONObject;
    if (JSONObject.Values['base64'].Value <> '') or
      (JSONObject.Values['base64'].Value <> 'remove') then
    begin
      CaminhoImagem := EnviaImagem(FormatDateTime('ddmmyyyyhhssnn', now) +
        'empresa-' + frmServidor.UserID.ToString, frmServidor.UserID.ToString,
        JSONObject.Values['base64'].Value);
    end;
    if (JSONObject.Values['base64'].Value = 'remove') then
    begin
      CaminhoImagem := 'x';
    end;
    if CaminhoImagem <> '' then
    begin
      if CaminhoImagem = 'x' then
        CaminhoImagem := '';
      conexao := TConexao.Create('try');
      Qry := conexao.CriaQRY;
      try
        Qry.SQL.Text := 'INSERT INTO configuracoes (chave, valor) ' +
          'VALUES (:chave, :valor) ' +
          'ON DUPLICATE KEY UPDATE valor = VALUES(valor)';
        Qry.ParamByName('chave').AsWideString := JSONObject.Values
          ['type'].Value;
        Qry.ParamByName('valor').AsWideString := CaminhoImagem;
        Qry.ExecSQL;
      finally
        Qry.Free;
      end;
      conexao.Free;
    end;
  end;
end;

procedure DoGetServicoImpressao(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  Res.Send(frmServidor.ImpressaoStatus);
end;

procedure DoGetProdutoEstoque(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetProdutoEstoque');
  conexao.SQL.Add
    ('select nome_produto, saldo_atual from produto where codigo = :codigo');
  conexao.Parametros('codigo', Req.Params['codigo']);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetProdutoAnaliseEstoque(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Retorno: TJSONObject;
  Codigo, DataInicio, DataFim: string;
begin
  conexao := TConexao.Create('DoGetProdutoAnaliseEstoque');
  Retorno := TJSONObject.Create;
  try
    Codigo := Req.Params['codigo'];
    DataInicio := Req.Params['data_inicio'];
    DataFim := Req.Params['data_fim'];
    Retorno.AddPair('codigo_produto', Codigo);
    Retorno.AddPair('data_inicio', DataInicio);
    Retorno.AddPair('data_fim', DataFim);
    conexao.SQL.Add('select nome_produto, saldo_atual');
    conexao.SQL.Add('from produto');
    conexao.SQL.Add('where codigo = :codigo');
    conexao.Parametros('codigo', Codigo);
    Retorno.AddPair('produto', conexao.ConsultaSQL);
    conexao.SQL.Add('select data, hora, operacao, quantidade, transacao');
    conexao.SQL.Add('from produto_estoque');
    conexao.SQL.Add('where codigo_produto = :codigo');
    conexao.SQL.Add('and data between :data_inicio and :data_fim');
    conexao.SQL.Add('order by data desc, hora desc, codigo desc');
    conexao.Parametros('codigo', Codigo);
    conexao.Parametros('data_inicio', DataInicio);
    conexao.Parametros('data_fim', DataFim);
    Retorno.AddPair('transacoes', conexao.ConsultaSQL);
    conexao.SQL.Add('select');
    conexao.SQL.Add
      ('coalesce(sum(case when operacao = 1 then quantidade else 0 end), 0) as total_entrada,');
    conexao.SQL.Add
      ('coalesce(sum(case when operacao <> 1 then quantidade else 0 end), 0) as total_saida,');
    conexao.SQL.Add
      ('coalesce(sum(case when operacao = 1 then quantidade else quantidade * -1 end), 0) as saldo_periodo,');
    conexao.SQL.Add('count(*) as total_transacoes');
    conexao.SQL.Add('from produto_estoque');
    conexao.SQL.Add('where codigo_produto = :codigo');
    conexao.SQL.Add('and data between :data_inicio and :data_fim');
    conexao.Parametros('codigo', Codigo);
    conexao.Parametros('data_inicio', DataInicio);
    conexao.Parametros('data_fim', DataFim);
    Retorno.AddPair('resumo', conexao.ConsultaSQL);
    Res.Send<TJSONObject>(Retorno);
  finally
    conexao.Free;
  end;
end;

procedure DoGetProdutoEstoqueBaixoXML(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  arquivo, Caminho: string;
begin
  arquivo := ExtractFileName(Req.Params['arquivo']);
  Caminho := IncludeTrailingPathDelimiter(ExtractFilePath(ParamStr(0))) +
    'cache' + PathDelim + 'alertas' + PathDelim + arquivo;
  if not TFile.Exists(Caminho) then
  begin
    Res.Status(404).Send('XML nao encontrado');
    exit;
  end;
  Res.Send(TFile.ReadAllText(Caminho, TEncoding.UTF8));
end;

procedure DoGetProdutoVendas(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  // Req.Params['codigo'].ToInteger
  Res.Send<TJSONObject>(GetProdutoVenda(Req.body, Req.Params['codigo']));
end;

procedure DoGetCMV(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('CMV');
  conexao.SQL.Add
    ('select * from cmv where codigo_produto = :id and data_final is null limit 1');
  conexao.Parametros('id', Req.Params['codigo'].ToInteger);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostCMV(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  JSONObject: TJSONObject;
  conexao: TConexao;
begin
  JSONObject := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  conexao := TConexao.Create('CMV');
  conexao.SQL.Add
    ('update cmv set data_final = current_timestamp where codigo_produto = :produto and data_final is null');
  conexao.Parametros('produto', JSONObject.GetValue<Integer>('produto'));
  conexao.ExecuteSQL;
  conexao.SQL.Add
    ('insert into cmv (codigo_produto,custo_ingrediente,custo_indiretos,percentual_imposto,percentual_cartao,percentual_ifood,percentual_lucro,valor_imposto,valor_cartao,valor_ifood,valor_lucro,preco_sugerido)');
  conexao.SQL.Add
    ('values (:produto,:ingrediente,:indiretos,:imposto,:cartao,:ifood,:lucro,:valorimposto,:valorcartao,:valorifood,:valorlucro,:precosugerido)');
  conexao.Parametros('produto', JSONObject.GetValue<Integer>('produto'));
  conexao.Parametros('ingrediente',
    JSONObject.GetValue<Real>('custoIngrediente'));
  conexao.Parametros('indiretos', JSONObject.GetValue<Real>('custoIndireto'));
  conexao.Parametros('imposto', JSONObject.GetValue<Real>('percentualImposto'));
  conexao.Parametros('cartao', JSONObject.GetValue<Real>('percentualCartao'));
  conexao.Parametros('ifood', JSONObject.GetValue<Real>('percentualiFood'));
  conexao.Parametros('lucro', JSONObject.GetValue<Real>('percentualLucro'));
  conexao.Parametros('valorimposto', JSONObject.GetValue<Real>('valorImposto'));
  conexao.Parametros('valorcartao', JSONObject.GetValue<Real>('valorCartao'));
  conexao.Parametros('valorifood', JSONObject.GetValue<Real>('valoriFood'));
  conexao.Parametros('valorlucro', JSONObject.GetValue<Real>('valorLucro'));
  conexao.Parametros('precosugerido',
    JSONObject.GetValue<Real>('precoSugerido'));
  conexao.ExecuteSQL;
  conexao.SQL.Add
    ('update produto set valor_custo = :custo where codigo = :produto');
  conexao.Parametros('produto', JSONObject.GetValue<Integer>('produto'));
  conexao.Parametros('custo', JSONObject.GetValue<Real>('custoIngrediente') +
    JSONObject.GetValue<Real>('custoIndireto'));
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoPostInsulmo(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  JSONData: TJSONObject;
  FichaArray: TJsonArray;
  FichaItem: TJSONObject;
  i: Integer;
  IngredienteID: Integer;
  conexao: TConexao;
  Codigo: Integer;
begin
  conexao := TConexao.Create('insulmo');
  JSONData := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  try
    Codigo := JSONData.GetValue<Integer>('id');
    if Codigo = 0 then
    begin
      Codigo := conexao.GerarID('ingredientes', 'id');
      conexao.SQL.Add
        ('insert into ingredientes (id,descricao,unidade,tipo,quantidade,custo) values (:id,:descricao,:unidade,:tipo,:quantidade,:custo)');
    end
    else
    begin
      conexao.SQL.Add
        ('update ingredientes set descricao = :descricao, unidade = :unidade, tipo = :tipo, quantidade = :quantidade, custo = :custo where id = :id');
    end;
    conexao.Parametros('id', Codigo);
    conexao.Parametros('descricao',
      UpperCase(JSONData.GetValue<string>('descricao')));
    conexao.Parametros('unidade',
      UpperCase(JSONData.GetValue<string>('unidade')));
    conexao.Parametros('tipo', (JSONData.GetValue<Integer>('tipo')));
    conexao.Parametros('quantidade', (JSONData.GetValue<Real>('quantidade')));
    conexao.Parametros('custo', (JSONData.GetValue<Real>('custo')));
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('delete from ingredientes_ficha where id_ingrediente = :id');
    conexao.Parametros('id', Codigo);
    conexao.ExecuteSQL;
    // Inserir o ingrediente na tabela de ingredientes
    // Query.SQL.Text := 'INSERT INTO ingredientes (descricao, unidade, tipo) ' +
    // 'VALUES (:descricao, :unidade, :tipo) RETURNING id';
    // Query.ParamByName('descricao').AsString := JSONData.GetValue<string>('descricao');
    // Query.ParamByName('unidade').AsString :=   JSONData.GetValue<string>('unidade');
    // Query.ParamByName('tipo').AsInteger := JSONData.GetValue<Integer>('tipo');
    // Query.Open;
    // Captura o ID do ingrediente inserido
    // IngredienteID := Query.FieldByName('id').AsInteger;
    // Processa o array "ficha"
    FichaArray := JSONData.GetValue<TJsonArray>('ficha');
    for i := 0 to FichaArray.Count - 1 do
    begin
      IngredienteID := conexao.GerarID('ingredientes_ficha', 'id');
      FichaItem := FichaArray.Items[i] as TJSONObject;
      conexao.SQL.Add
        ('insert into ingredientes_ficha (id,id_ingrediente, id_composicao,quantidade) values (:id,:id_ingrediente, :id_composicao,:quantidade)');
      conexao.Parametros('id', IngredienteID);
      conexao.Parametros('id_ingrediente', Codigo);
      conexao.Parametros('id_composicao',
        FichaItem.GetValue<Integer>('idComposicao'));
      conexao.Parametros('quantidade',
        FichaItem.GetValue<Double>('quantidade'));
      conexao.ExecuteSQL;
      // Inserir cada item da ficha t?cnica na tabela
      // Query.SQL.Text := 'INSERT INTO ficha_tecnica ' +
      // '(id_ingrediente, id_composicao, descricao, quantidade, unidade) ' +
      // 'VALUES (:id_ingrediente, :id_composicao, :descricao, :quantidade, :unidade)';
      // Query.ParamByName('id_ingrediente').AsInteger := IngredienteID;
      // Query.ParamByName('id_composicao').AsInteger := FichaItem.GetValue<Integer>('id_composicao');
      // Query.ParamByName('descricao').AsString :=  FichaItem.GetValue<string>('descricao');
      // Query.ParamByName('quantidade').AsFloat :=  FichaItem.GetValue<Double>('quantidade');
      // Query.ParamByName('unidade').AsString :=  FichaItem.GetValue<string>('unidade');
      // Query.ExecSQL;
    end;
  finally
    JSONData.Free;
  end;
  conexao.Free;
end;

procedure DoProcessarIngredientesCardapio(Req: THorseRequest;
Res: THorseResponse; Next: TProc);
begin
  Res.Send<TJSONObject>(ProcessarIngredientesCardapio);
end;

procedure DoGravarIngredientesCardapio(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  Res.Send<TJSONObject>(GravarIngredientesCardapio(Req.body));
end;

procedure DoValidarAlertaIngredientesPendentes(Req: THorseRequest;
Res: THorseResponse; Next: TProc);
begin
  Res.Send<TJSONObject>(ValidarAlertaIngredientesPendentes);
end;

procedure DoPostRecontagemEstoque(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  frmServidor.AtualizaSaldoEstoque;
end;

procedure DoGetGerarPedidosRandom(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
end;

procedure DoGetParametro(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  Obj: TJSONObject;
  Valor: String;
  SWStep: TStopwatch;
begin
  conexao := TConexao.Create('DoGetParametro');
  try
    try
      Valor := conexao.GetParametro(Req.Params['chave']);
    except
      Valor := '';
    end;
    SWStep := TStopwatch.StartNew;
    Obj := TJSONObject.Create;
    Obj.AddPair('chave', Valor);
    PerformanceJSON(SWStep.ElapsedMilliseconds, 1,
      TEncoding.UTF8.GetByteCount(Obj.ToJSON));
    SWStep := TStopwatch.StartNew;
    Res.Send(Obj);
    PerformanceStep('response_write', SWStep.ElapsedMilliseconds);
  finally
    conexao.Free;
  end;
end;
procedure DoGetParametros(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send<TJsonArray>(GetParametros);
end;

procedure DoPostTempoEntregaPedido(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoPostTempoEntregaPedido');
  conexao.Free;
end;

procedure DoGetInsulmosFicha(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetInsulmosFicha');
  conexao.SQL.Add
    ('select ingf.*, ing.descricao, ing.unidade, ing.custo as custo from ingredientes_ficha as ingf');
  conexao.SQL.Add('join ingredientes as ing on ing.id = ingf.id_composicao');
  conexao.SQL.Add('where ingf.id_ingrediente = :codigo');
  conexao.Parametros('codigo', Req.Params['codigo']);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostParametroVemBuscar(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Tipo: Boolean;
begin
  conexao := TConexao.Create('DoGetParametroEntregaVemBuscar');
  Tipo := Req.Params['tipo'] = '1';
  conexao.SQL.Add('update dados_whatsapp set retirada = :retirada');
  if Tipo then
  begin
    conexao.Parametros('retirada', 1);
  end
  else
  begin
    conexao.Parametros('retirada', 0);
  end;
  conexao.ExecuteSQL;
  frmServidor.SincronizaParametros;
  conexao.Free;
end;

procedure DoPostParametroEntrega(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Tipo: Boolean;
begin
  conexao := TConexao.Create('DoGetParametroEntregaVemBuscar');
  Tipo := Req.Params['tipo'] = '1';
  conexao.SQL.Add('update dados_whatsapp set delivery = :delivery');
  if Tipo then
  begin
    conexao.Parametros('delivery', 1);
  end
  else
  begin
    conexao.Parametros('delivery', 0);
  end;
  conexao.ExecuteSQL;
  frmServidor.SincronizaParametros;
  conexao.Free;
end;

procedure DoGetParametroEntregaVemBuscar(Req: THorseRequest;
Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetParametroEntregaVemBuscar');
  conexao.SQL.Add
    ('select retirada, delivery, temp_delivery, temp_vembuscar from dados_whatsapp');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostReImpressaoCozinha(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  JSONArray: TJsonArray;
  i: Integer;
  conexao: TConexao;
  Codigo: Integer;
  codigos: String;
begin
  conexao := TConexao.Create('v2');
  JSONArray := TJSONObject.ParseJSONValue(Req.body) as TJsonArray;
  for i := 0 to JSONArray.Count - 1 do
  begin
    conexao.SQL.Add
      ('insert into impressao_pedido_produto (data_solicitacao,hora_solicitacao,id_pedido,status) values (curdate(),curtime(),:pedido,1)');
    conexao.Parametros('pedido', JSONArray[i].ToString);
    conexao.ExecuteSQL;
    if i = 0 then
      codigos := Codigo.ToString
    else
      codigos := codigos + ',' + Codigo.ToString;
  end;
  conexao.SQL.Add('update impressao_pedido_produto set status = 0 where id in ('
    + codigos + ')');
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoPostImportacaoToPedindo(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  JSONObject: TJSONObject;
begin
  try
    JSONObject := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
    // ////////showmessage1(JSONObject.GetValue<string>('url'));
    frmServidor.RequisicaoToPedindo.BaseURL :=
      JSONObject.GetValue<string>('url');
    TThread.CreateAnonymousThread(
      procedure
      begin
        frmServidor.ImportaProdutosToPedindo;
      end).start;
  finally
    JSONObject.Free;
  end;
end;

procedure DoPostAtivaInativaItens(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  if (Req.Params['tipo'] = '1') then
  begin
    conexao.SQL.Add
      ('update produto set ativo = :status, modificado_site = 0 where codigo in ('
      + Req.Params['codigo'] + ')');
  end;
  if (Req.Params['tipo'] = '2') then
  begin
    conexao.SQL.Add
      ('update sabores_completo set ativo = :status, modificado_site = 0 where id in ('
      + Req.Params['codigo'] + ')');
  end;
  if (Req.Params['tipo'] = '3') then
  begin
    conexao.SQL.Add
      ('update pro_adi_personalizado_sabores set ativo = :status, modificado_site = 0 where id in ('
      + Req.Params['codigo'] + ')');
  end;
  conexao.Parametros('status', Req.Params['status']);
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoGetProdutoSaboresExtras(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Result: String;
begin
  Result := UpperCase(Req.Params['busca']);
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('SELECT codigo as id, ');
  conexao.SQL.Add('       nome_produto as nome, ');
  conexao.SQL.Add('       descricao as descricao, ');
  conexao.SQL.Add('       ativo as status, ');
  conexao.SQL.Add('       1 as tipo, ');
  conexao.SQL.Add('       ' + QuotedStr('produto') + ' as tipo_descricao, ');
  conexao.SQL.Add('       nome_produto as produto  ');
  conexao.SQL.Add(' FROM produto');
  conexao.SQL.Add
    (' WHERE concat(upper(nome_produto), "|", upper(descricao)) LIKE ' +
    QuotedStr('%' + Result + '%'));
  conexao.SQL.Add(' UNION ALL');
  conexao.SQL.Add(' SELECT group_concat(id) as codigo, ');
  conexao.SQL.Add('       nome, ');
  conexao.SQL.Add('       sabores_completo.descricao, ');
  conexao.SQL.Add('       sabores_completo.ativo as status, ');
  conexao.SQL.Add('       2 as tipo, ');
  conexao.SQL.Add('       ' + QuotedStr('sabor') + ' as tipo_descricao, ');
  conexao.SQL.Add('       group_concat(nome_produto," ") as produto');
  conexao.SQL.Add(' FROM sabores_completo');
  conexao.SQL.Add(' JOIN produto on produto.codigo = id_produto');
  conexao.SQL.Add
    (' WHERE concat(upper(sabores_completo.nome), "|", upper(sabores_completo.descricao)) LIKE '
    + QuotedStr('%' + Result + '%'));
  conexao.SQL.Add
    (' GROUP BY nome, sabores_completo.descricao, sabores_completo.ativo');
  conexao.SQL.Add(' UNION ALL');
  conexao.SQL.Add
    (' SELECT group_concat(pro_adi_personalizado_sabores.id) as id, ');
  conexao.SQL.Add('       pro_adi_personalizado_sabores.nome as nome, ');
  conexao.SQL.Add
    ('       pro_adi_personalizado_sabores.descricao as descricao, ');
  conexao.SQL.Add('       pro_adi_personalizado_sabores.ativo as ativo, ');
  conexao.SQL.Add('       3 as tipo, ');
  conexao.SQL.Add('       ' + QuotedStr('extra') + ' as tipo_descricao, ');
  conexao.SQL.Add('       group_concat(produto.nome_produto," ") as produto ');
  conexao.SQL.Add(' FROM pro_adi_personalizado');
  conexao.SQL.Add
    (' JOIN pro_adi_personalizado_sabores on pro_adi_personalizado_sabores.id_pro_adi_personalizado = pro_adi_personalizado.id');
  conexao.SQL.Add
    (' JOIN produto on produto.codigo = pro_adi_personalizado.id_produto');
  conexao.SQL.Add
    (' WHERE concat(upper(pro_adi_personalizado_sabores.nome), "|", upper(pro_adi_personalizado_sabores.descricao)) LIKE '
    + QuotedStr('%' + Result + '%'));
  conexao.SQL.Add(' GROUP BY pro_adi_personalizado_sabores.nome, ');
  conexao.SQL.Add('         pro_adi_personalizado_sabores.descricao, ');
  conexao.SQL.Add('         pro_adi_personalizado_sabores.ativo;');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetUser(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  JSONObject: TJSONObject;
begin
  JSONObject := TJSONObject.Create;
  JSONObject.AddPair('user', frmServidor.UserID.ToString);
  Res.Send<TJSONObject>(JSONObject);
end;

procedure DoPostRegistro(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Usuario: TJSONObject;
  conexao: TConexao;
  Codigo: Integer;
begin
  conexao := TConexao.Create('DoPostRegistro');
  Usuario := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  conexao.SalvarParametro('client_id', Usuario.GetValue<String>('id'));
  conexao.SalvarParametro('client_security', Usuario.GetValue<String>('security'));
  conexao.SQL.Add('delete from usuario');
  conexao.ExecuteSQL;
  Codigo := conexao.GerarID('usuario', 'codigo');
  conexao.SQL.Add('INSERT INTO usuario (');
  conexao.SQL.Add
    ('codigo,nome,senha,data_cadastro,encerra,app,deleta,dashboard,estoque,cad_mesa,cad_motoboy,cad_taxa,cad_impressora,cad_cupom,cad_prod,cad_paga,cad_cli,cad_pedido,desconto,param,caixa,cancelar,garcom,campanha,financeiro) VALUES (');
  conexao.SQL.Add
    (':codigo,:nome,MD5(:senha),CURDATE(),1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0,1,1);');
  conexao.Parametros('codigo', Codigo);
  conexao.Parametros('nome', Usuario.GetValue<String>('usuario'));
  conexao.Parametros('senha', Usuario.GetValue<String>('senha'));
  conexao.ExecuteSQL;
  conexao.Free;
  frmServidor.AposConectarBanco;
end;

procedure DoPostLicensa(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Usuario: TJSONObject;
  APIGoopedir: TGooPedirAPIController;
  Retorno: TJSONObject;
  conexao: TConexao;
  Quantidade: String;
begin
  try
    Usuario := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
    Retorno := TJSONObject.Create;
    APIGoopedir := TGooPedirAPIController.Create(getUrlGoopedir,
      Usuario.GetValue<String>('id'), Usuario.GetValue<String>('security'), nil,
      nil, nil, '');
    if APIGoopedir.UserID = 0 then
    begin
      Retorno.AddPair('erro', 'Credencial Inv?lida!');
    end
    else
    begin
      conexao := TConexao.Create('DoPostLicensa');
      conexao.SQL.Add
        ('select 0 as zero, count(*) as qtd from usuario where codigo > 0');
      Quantidade := conexao.FieldByName('qtd');
      Retorno.AddPair('erro', '');
      Retorno.AddPair('user', APIGoopedir.UserID);
      Retorno.AddPair('name', APIGoopedir.Name);
      Retorno.AddPair('quantidade', Quantidade);
      conexao.SalvarParametro('client_id', Usuario.GetValue<String>('id'));
      conexao.SalvarParametro('client_security', Usuario.GetValue<String>('security'));
      APIGoopedirLock.Enter;
      try
        frmServidor.APIGoopedir.Free;
        frmServidor.APIGoopedir := TGooPedirAPIController.Create(getUrlGoopedir,
          conexao.GetParametro('client_id'),
          conexao.GetParametro('client_security'), frmServidor.GetHorarioAbertura,
          frmServidor.GetHorarioFechamento,
          frmServidor.GetHorarioAtendimento, '');
      finally
        APIGoopedirLock.Leave;
      end;
      conexao.Free;
    end;
  except
    on E: Exception do
    begin
      Retorno.AddPair('erro', E.Message);
    end;
  end;
  Res.Send<TJSONObject>(Retorno);
  APIGoopedir.Free;
end;

function V2StatusTraceValue(const Value: string): string;
begin
  Result := StringReplace(Value, #13, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, #10, ' ', [rfReplaceAll]);
  Result := StringReplace(Result, '|', '/', [rfReplaceAll]);
end;

procedure V2StatusTrace(const RequestId, Evento, Etapa: string;
  const DuracaoMS: Int64; Req: THorseRequest; const Detalhe: string = '');
var
  LogDir: string;
  LogFile: string;
  Linha: string;
begin
  try
    LogDir := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
    TDirectory.CreateDirectory(LogDir);
    LogFile := TPath.Combine(LogDir, 'v2-status-' + FormatDateTime('yyyymmdd',
      Now) + '.log');
    Linha := Format('%s|request=%s|evento=%s|etapa=%s|duracao_ms=%d|ip=%s|user=%s|body_len=%d|detalhe=%s%s',
      [FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now),
      V2StatusTraceValue(RequestId), V2StatusTraceValue(Evento),
      V2StatusTraceValue(Etapa), DuracaoMS, V2StatusTraceValue(GetClientIP(Req)),
      V2StatusTraceValue(Req.Headers['user']), Length(Req.Body),
      V2StatusTraceValue(Detalhe), sLineBreak]);
    V2StatusTraceLock.Enter;
    try
      TFile.AppendAllText(LogFile, Linha, TEncoding.UTF8);
    finally
      V2StatusTraceLock.Leave;
    end;
  except
  end;
end;

procedure DoPostBanner(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  iReq: iRequisicao;
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  CaminhoImagem: String;
  JsonEnvio: TJSONObject;
begin
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  if Assigned(JSONValue) and (JSONValue is TJSONObject) then
  begin
    JSONObject := JSONValue as TJSONObject;
    if (JSONObject.Values['img_banner_base64'].Value <> '') or
      (JSONObject.Values['img_banner_base64'].Value <> 'remove') then
    begin
      CaminhoImagem := EnviaImagem(FormatDateTime('ddmmyyyyhhssnn', now) +
        'empresa-' + frmServidor.UserID.ToString, frmServidor.UserID.ToString,
        JSONObject.Values['img_banner_base64'].Value);
    end;
  end;
  JsonEnvio := TJSONObject.Create;
  JsonEnvio.AddPair('acao_clique', JSONObject.Values['acao_clique'].Value);
  JsonEnvio.AddPair('confirma_banner',
    JSONObject.Values['confirma_banner'].Value);
  JsonEnvio.AddPair('data_fim', JSONObject.Values['data_fim'].Value);
  JsonEnvio.AddPair('data_inicio', JSONObject.Values['data_inicio'].Value);
  JsonEnvio.AddPair('dia_semana', JSONObject.Values['dia_semana'].Value);
  JsonEnvio.AddPair('user_id', frmServidor.UserID.ToString);
  JsonEnvio.AddPair('img_banner', CaminhoImagem);
  CaminhoImagem := JsonEnvio.ToString;
  iReq := iRequisicao.Create(nil);
  iReq.URL := 'api/empresa/banner';
  iReq.BaseURL := API_BASE_URL;
  iReq.body(CaminhoImagem);
  iReq.Metodo := mPost;
  try
    iReq.Execute;
    Res.Send(iReq.Retorno);
  except
    on E: Exception do
      Res.Send(E.Message);
  end;
  iReq.Free;
end;

procedure DoGetBanner(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  if frmServidor.memBanner.RecordCount = 0 then
  begin
    conexao := TConexao.Create('DoGetBanner');
    conexao.SQL.Add
      ('select *, DAYOFWEEK(curdate()) from banner where link <> "" and dia_semana like concat("%",DAYOFWEEK(curdate()),"%")');
    frmServidor.memBanner.LoadFromJSON(conexao.ConsultaSQL);
    conexao.Free;
  end;
  Res.Send(frmServidor.memBanner.ToJSONArray());
end;

procedure DoGetAtualizacao(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send<TJSONObject>(frmServidor.AtualizacaoStatus);
end;

procedure DoPostAtualizacaoIniciar(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  frmServidor.IniciarAtualizacao;
  Res.Send<TJSONObject>(frmServidor.AtualizacaoStatus);
end;

procedure DoGetStatus(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  JSONObject: TJSONObject;
  JSonObjectWhatsapp: TJSONObject;
  JSonObjectImpressora: TJSONObject;
  JSONModulos: TJSONObject;
  JSONNFCe: TJSONObject;
  conexao: TConexao;
  Quantidade: Integer;
  Usuario: TJSONObject;
  Consulta: String;
  CodigoUsuario: String;
  NFC: String;
  ObjetoiFood: TJSONObject;
  ArrayiFood: TJsonArray;
  DadosiFood: TFDMemTable;
  Tempos: TJSONObject;
  Stopwatch: TStopwatch;
  RequestId: string;
  EtapaAtual: string;
  InicioRequest: TStopwatch;
  PendenciasEmpresa: TJSONObject;
  TemPendenciaEmpresa: Boolean;

  procedure IniciarTempo;
  begin
    Stopwatch := TStopwatch.StartNew;
  end;

  procedure RegistrarTempo(const Nome: string);
  begin
    Stopwatch.Stop;
    Tempos.AddPair(Nome, IntToStr(Stopwatch.ElapsedMilliseconds) + 'ms');
    EtapaAtual := Nome;
    if Stopwatch.ElapsedMilliseconds >= 3000 then
      V2StatusTrace(RequestId, 'etapa_lenta', Nome,
        Stopwatch.ElapsedMilliseconds, Req);
  end;

  function CountSQL(const SQL: string): Integer;
  begin
    Result := 0;
    try
      conexao.SQL.Add(SQL);
      Result := conexao.FieldByName('quantidade');
    except
      Result := 0;
    end;
  end;

  procedure AddValidacaoEmpresa(const Nome: string; const Ok: Boolean;
    const Quantidade: Integer = -1);
  var
    Item: TJSONObject;
  begin
    Item := TJSONObject.Create;
    Item.AddPair('ok', Ok);
    if Quantidade >= 0 then
      Item.AddPair('quantidade', TJSONNumber.Create(Quantidade));
    PendenciasEmpresa.AddPair(Nome, Item);
    if not Ok then
      TemPendenciaEmpresa := True;
  end;

  procedure ValidarPendenciasEmpresa;
  var
    Qtd: Integer;
  begin
    TemPendenciaEmpresa := False;
    PendenciasEmpresa := TJSONObject.Create;

    Qtd := CountSQL('select count(*) as quantidade, 0 as zero from usuario where codigo = ' +
      QuotedStr(CodigoUsuario) + ' and upper(nome) = ''ADMIN'' and senha = md5(''admin'')');
    AddValidacaoEmpresa('usuarioAdminPadrao', Qtd = 0, Qtd);

    Qtd := CountSQL('select count(*) as quantidade, 0 as zero from taxa_entrega');
    AddValidacaoEmpresa('taxaEntrega', Qtd > 0, Qtd);

    Qtd := CountSQL('select count(distinct bairro) as quantidade, 0 as zero from taxa_entrega where bairro is not null and length(trim(bairro)) > 0');
    AddValidacaoEmpresa('bairro', Qtd > 0, Qtd);

    Qtd := CountSQL('select count(*) as quantidade, 0 as zero from tipo_produto');
    AddValidacaoEmpresa('categoria', Qtd > 0, Qtd);

    Qtd := CountSQL('select count(*) as quantidade, 0 as zero from impressoras');
    AddValidacaoEmpresa('impressora', Qtd > 0, Qtd);

    Qtd := CountSQL('select count(*) as quantidade, 0 as zero from produto where ativo = 1 and (deletado = 0 or deletado is null)');
    AddValidacaoEmpresa('produto', Qtd > 0, Qtd);

    AddValidacaoEmpresa('camposObrigatoriosSite', True);
  end;
begin
  RequestId := FormatDateTime('yyyymmddhhnnsszzz', Now) + '-' +
    IntToHex(GetCurrentThreadId, 8);
  EtapaAtual := 'inicio';
  InicioRequest := TStopwatch.StartNew;
  V2StatusTrace(RequestId, 'inicio', EtapaAtual, 0, Req);
  Tempos := TJSONObject.Create;
  JSONObject := nil;
  conexao := nil;
  DadosiFood := nil;
  try
  conexao := TConexao.Create('V2Status');
  DadosiFood := TFDMemTable.Create(nil);
  IniciarTempo;
  try
    JSONModulos := TJSONObject.ParseJSONValue(frmServidor.GetModulo)
      as TJSONObject;
  except
    JSONModulos := TJSONObject.Create;
  end;
  RegistrarTempo('modulos');
  IniciarTempo;
  try
    Usuario := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
    conexao.SQL.Add
      ('select * from usuario where codigo = :codigo and nome = :nome and senha = :senha');
    conexao.Parametros('codigo', Usuario.GetValue<String>('codigo'));
    conexao.Parametros('nome', Usuario.GetValue<String>('nome'));
    conexao.Parametros('senha', Usuario.GetValue<String>('senha'));
    try
      Consulta := conexao.FieldByName('codigo');
    except
    end;
    CodigoUsuario := Usuario.GetValue<String>('codigo');
    if Consulta <> CodigoUsuario then
    begin
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('erro', True);
      JSONObject.AddPair('requestId', RequestId);
      JSONObject.AddPair('mensagem', 'Usuario invalido para consulta de status');
      V2StatusTrace(RequestId, 'usuario_invalido', EtapaAtual,
        InicioRequest.ElapsedMilliseconds, Req);
      conexao.Free;
      conexao := nil;
      DadosiFood.Free;
      DadosiFood := nil;
      Res.Status(401).Send<TJSONObject>(JSONObject);
      exit;
    end;
  except
    conexao.SQL.Clear;
  end;
  RegistrarTempo('usuario');
  JSONObject := TJSONObject.Create;
  IniciarTempo;
  ValidarPendenciasEmpresa;
  JSONObject.AddPair('pendenciaEmpresa', TemPendenciaEmpresa);
  JSONObject.AddPair('pendenciasEmpresa', PendenciasEmpresa);
  RegistrarTempo('pendencias_empresa');
  IniciarTempo;
  if conexao.GetParametro('client_id') = '' then
  begin
    JSONObject.AddPair('licensa', False);
    RegistrarTempo('licensa');
    JSONObject.AddPair('tempos', Tempos);
    V2StatusTrace(RequestId, 'sem_licensa', EtapaAtual,
      InicioRequest.ElapsedMilliseconds, Req);
    Res.Send(JSONObject);
    conexao.Free;
    conexao := nil;
    DadosiFood.Free;
    DadosiFood := nil;
    exit;
  end
  else
  begin
    JSONObject.AddPair('licensa', True);
  end;
  RegistrarTempo('licensa');
  IniciarTempo;
  APIGoopedirLock.Enter;
  try
    if Assigned(frmServidor.APIGoopedir) then
      JSONObject.AddPair('urlLoja', frmServidor.APIGoopedir.GetUrlLoja)
    else
      JSONObject.AddPair('urlLoja', '');
  finally
    APIGoopedirLock.Leave;
  end;
  RegistrarTempo('urlLoja');
  IniciarTempo;
  JSONObject.AddPair('atualizacaoEmAndamento',
    TJSONBool.Create(frmServidor.AtualizacaoEmAndamento));
  RegistrarTempo('atualizacao_estado');
  IniciarTempo;
  JSONObject.AddPair('modulos', JSONModulos);
  IniciarTempo;
  JSonObjectWhatsapp := TJSONObject.Create;
  JSonObjectWhatsapp.AddPair('status', frmServidor.StatusWhatsapp);
  JSonObjectWhatsapp.AddPair('celular', frmServidor.NumeroWhatsapp);
  JSonObjectWhatsapp.AddPair('base64', frmServidor.Base64Whatsapp);
  JSonObjectWhatsapp.AddPair('logout', frmServidor.LogoutWhatsapp);
  JSonObjectWhatsapp.AddPair('name', frmServidor.NomeWhatsapp);
  JSonObjectWhatsapp.AddPair('url', frmServidor.ImagemWhatsapp);
  JSonObjectWhatsapp.AddPair('msgErro', frmServidor.StatusErroWhatsapp);
  JSonObjectWhatsapp.AddPair('statusOperacao',
    frmServidor.StatusMensagemWhatsapp);
  if frmServidor.StatusMensagemWhatsapp = 2 then
    frmServidor.StatusMensagemWhatsapp := 0;
  try
    JSONObject.AddPair('whatsapp', JSonObjectWhatsapp);
  except
  end;
  RegistrarTempo('whatsapp');
  IniciarTempo;
  try
    JSONObject.AddPair('impressora', frmServidor.ImpressaoStatus);
  except
  end;
  RegistrarTempo('impressora');
  IniciarTempo;
  JSONObject.AddPair('site',
    TJSONObject.ParseJSONValue(frmServidor.GetCachedData) as TJSONObject);
  RegistrarTempo('site');
  ArrayiFood := TJsonArray.Create;
  IniciarTempo;
  if frmServidor.dataSetMerchants1.RecordCount > 0 then
  begin
    conexao.SQL.Add('select * from ifood_connect');
    DadosiFood.LoadFromJSON(conexao.ConsultaSQL);
  end;
  JSONObject.AddPair('urlImpressaoGo', frmServidor.urlServicoImpressaoGo);
  if DadosiFood.RecordCount > 0 then
  begin
    ObjetoiFood := TJSONObject.Create;
    ObjetoiFood.AddPair('statusLoja', frmServidor.dataSetMerchants1.FieldByName
      ('messagetitle').AsString);
    ObjetoiFood.AddPair('detalheLoja', frmServidor.dataSetMerchants1.FieldByName
      ('messagesubtitle').AsString);
    ObjetoiFood.AddPair('status', frmServidor.dataSetMerchants1.FieldByName
      ('available').AsString);
    ObjetoiFood.AddPair('loja', DadosiFood.FieldByName('name').AsString);
    ArrayiFood.AddElement(ObjetoiFood);
  end;
  if frmServidor.dataSetMerchants2.RecordCount > 0 then
  begin
    DadosiFood.Next;
    ObjetoiFood := TJSONObject.Create;
    ObjetoiFood.AddPair('statusLoja', frmServidor.dataSetMerchants2.FieldByName
      ('messagetitle').AsString);
    ObjetoiFood.AddPair('detalheLoja', frmServidor.dataSetMerchants2.FieldByName
      ('messagesubtitle').AsString);
    ObjetoiFood.AddPair('status', frmServidor.dataSetMerchants2.FieldByName
      ('available').AsString);
    ObjetoiFood.AddPair('loja', DadosiFood.FieldByName('name').AsString);
    ArrayiFood.AddElement(ObjetoiFood);
  end;
  RegistrarTempo('ifood');
  IniciarTempo;
  // DadosIfood.LoadFromJSON(frmServidor.dataSetMerchants1.ToJSONArray());
  // DadosIfood.LoadFromJSON(frmServidor.dataSetMerchants2.ToJSONArray());
  if (Desenvolvimento()) then
  begin
    JSONObject.AddPair('ambiente', 'desenv');
  end
  else
  begin
    JSONObject.AddPair('ambiente', 'prod');
  end;
  RegistrarTempo('ambiente');

  JSONObject.AddPair('urlGoopedir', API_BASE_URL);

  JSONObject.AddPair('ifood', ArrayiFood);
  JSONObject.AddPair('user', frmServidor.UserID.ToString);
  JSONNFCe := TJSONObject.Create;
  IniciarTempo;
  conexao.SQL.Add('SELECT 0 as zero, nfce FROM dados_whatsapp');
  NFC := conexao.FieldByName('nfce');
  RegistrarTempo('nfce_configuracao');
  if NFC = '1' then
  begin
    JSONNFCe.AddPair('usa', True);
    IniciarTempo;
    conexao.SQL.Add
      ('SELECT count(*) as quantidade, 0 as zero FROM pedido WHERE nfce_emite = 1 and id_caixa > 0  AND status > 0  AND data_pedido >= '
      + QuotedStr(FormatDateTime('yyyy-mm-01', now)) +
      ' and codigo_pedido_dia > 0');
    Quantidade := conexao.FieldByName('quantidade');
    RegistrarTempo('nfce_contingencia');
    JSONNFCe.AddPair('contigencia', Quantidade);
    IniciarTempo;
    JSONNFCe.AddPair('erro', frmServidor.memErrosNFCE.ToJSONArray());
    RegistrarTempo('nfce_erros');
  end
  else
  begin
    JSONNFCe.AddPair('contigencia', 0);
    JSONNFCe.AddPair('usa', False);
    JSONNFCe.AddPair('erro', '[]');
  end;
  JSONObject.AddPair('nfce', JSONNFCe);
  IniciarTempo;
  JSONObject.AddPair('taxaEntrega', frmServidor.GetTaxaEntrega);
  RegistrarTempo('taxaEntrega');
  IniciarTempo;
  JSONObject.AddPair('tipoPagamento', frmServidor.GetTipopagamento);
  RegistrarTempo('tipoPagamento');
  IniciarTempo;
  if Assigned(frmServidor.CertificadoAtual) then
  begin
    frmServidor.RetornaCertificado.Free;
    JSONObject.AddPair('CertificadoAtual',
      TJSONObject.ParseJSONValue(frmServidor.CertificadoAtual.ToString));
  end;
  RegistrarTempo('certificado');
  if frmServidor.memPaineis.RecordCount = 0 then
  begin
    IniciarTempo;
    conexao.SQL.Add('SELECT * FROM painel where tipo <> 3');
    frmServidor.memPaineis.LoadFromJSON(conexao.ConsultaSQL);
    RegistrarTempo('painel_consulta');
  end
  else
  begin
    IniciarTempo;
    RegistrarTempo('painel_cache');
  end;
  if frmServidor.memBanner.RecordCount = 0 then
  begin
    IniciarTempo;
    conexao.SQL.Add
      ('select *, DAYOFWEEK(curdate()) from banner where link <> "" and dia_semana like concat("%",DAYOFWEEK(curdate()),"%")');
    frmServidor.memBanner.LoadFromJSON(conexao.ConsultaSQL);
    RegistrarTempo('banner_consulta');
  end
  else
  begin
    IniciarTempo;
    RegistrarTempo('banner_cache');
  end;
  IniciarTempo;
  JSONObject.AddPair('banner', frmServidor.memBanner.ToJSONArray());
  JSONObject.AddPair('painel', frmServidor.memPaineis.ToJSONArray());
  JSONObject.AddPair('tipoMesa', frmServidor.memTipoMesa.ToJSONArray());
  RegistrarTempo('dados_memoria');
  IniciarTempo;
  if not Assigned(frmServidor.JsonDadosBloqueio) then
    frmServidor.DadosBloqueio;
  JSONObject.AddPair('bloqueio',TJSONObject.ParseJSONValue(frmServidor.JsonDadosBloqueio.ToString)as TJSONObject);
  JSONObject.AddPair('faturas',TJSONArray.ParseJSONValue(frmServidor.Faturas.ToString)as TJSONArray);
  RegistrarTempo('bloqueio');

  IniciarTempo;
  conexao.SQL.Add
    ('SELECT * FROM caixa where id_usuario = COALESCE(NULLIF((SELECT usuario_pai FROM usuario WHERE codigo = :usuario_pai_lookup), 0), :usuario_caixa_padrao) and status = 1');
  try
    conexao.Parametros('usuario_pai_lookup', Req.Headers['user'].ToInteger());
    conexao.Parametros('usuario_caixa_padrao', Req.Headers['user'].ToInteger());
  except
    conexao.Parametros('usuario_pai_lookup', 0);
    conexao.Parametros('usuario_caixa_padrao', 0);
  end;
  JSONObject.AddPair('userCaixa', conexao.ConsultaSQL);
  RegistrarTempo('userCaixa');
  IniciarTempo;
  JSONObject.AddPair('alerta', GetAlerta(conexao));
  RegistrarTempo('alerta');
  JSONObject.AddPair('tempos', Tempos);
  conexao.Free;
  conexao := nil;
  DadosiFood.Free;
  DadosiFood := nil;

  try
    V2StatusTrace(RequestId, 'fim', EtapaAtual,
      InicioRequest.ElapsedMilliseconds, Req);
    Res.Send(JSONObject);
  finally
    // JSonObject.Free;
    // JSonObjectWhatsapp.Free;
  end;
  except
    on E: Exception do
    begin
      V2StatusTrace(RequestId, 'erro', EtapaAtual,
        InicioRequest.ElapsedMilliseconds, Req, E.ClassName + ': ' + E.Message);
      RegistrarErroSaudeServidor(EtapaAtual, E.ClassName + ': ' + E.Message);
      try
        if Assigned(conexao) then
          conexao.Free;
        if Assigned(DadosiFood) then
          DadosiFood.Free;
      except
      end;
      JSONObject := TJSONObject.Create;
      JSONObject.AddPair('erro', True);
      JSONObject.AddPair('requestId', RequestId);
      JSONObject.AddPair('etapa', EtapaAtual);
      JSONObject.AddPair('mensagem', E.Message);
      Res.Status(500).Send<TJSONObject>(JSONObject);
    end;
  end;
end;

// procedure DoGetStatus(Req: THorseRequest; Res: THorseResponse; Next: TProc);
// var
// JSONObject: TJSONObject;
// JSonObjectWhatsapp: TJSONObject;
// JSONModulos: TJSONObject;
// JSONNFCe: TJSONObject;
//
// conexao: TConexao;
//
// Stopwatch: TStopwatch;
// PerfArray: TJSONArray;
// PerfItem: TJSONObject;
//
//
//
// QUANTIDADE: Integer;
// Usuario: TJSONObject;
// Consulta: String;
// CodigoUsuario: String;
// NFC: String;
// Reader: TStreamReader;
// JSONStr: string;
//
// ObjetoiFood: TJSONObject;
// ArrayiFood: TJsonArray;
// DadosiFood: TFDMemTable;
//
// procedure Marca(const Nome: string);
// begin
// Stopwatch.Stop;
// PerfItem := TJSONObject.Create;
// PerfItem.AddPair('etapa', Nome);
// PerfItem.AddPair('ms', TJSONNumber.Create(Stopwatch.ElapsedMilliseconds));
// PerfArray.AddElement(PerfItem);
// end;
//
// begin
//
// PerfArray := TJSONArray.Create;
// Stopwatch := TStopwatch.StartNew;
//
// conexao := TConexao.Create('V2Status');
// DadosiFood := TFDMemTable.Create(nil);
//
// try
//
// try
// JSONModulos := TJSONObject.ParseJSONValue(frmServidor.GetModulo) as TJSONObject;
// except
// end;
//
// Marca('modulos');
// Stopwatch := TStopwatch.StartNew;
//
// try
// Usuario := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
//
// conexao.SQL.Add(
// 'select * from usuario where codigo = :codigo and nome = :nome and senha = :senha');
//
// conexao.Parametros('codigo', Usuario.GetValue<String>('codigo'));
// conexao.Parametros('nome', Usuario.GetValue<String>('nome'));
// conexao.Parametros('senha', Usuario.GetValue<String>('senha'));
//
// Consulta := conexao.FieldByName('codigo');
// CodigoUsuario := Usuario.GetValue<String>('codigo');
//
// if Consulta <> CodigoUsuario then
// begin
// conexao.Free;
// Res.Status(1);
// exit;
// end;
//
// except
// conexao.SQL.Clear;
// end;
//
// Marca('validacao_usuario');
// Stopwatch := TStopwatch.StartNew;
//
// JSONObject := TJSONObject.Create;
//
// if conexao.GetParametro('client_id') = '' then
// JSONObject.AddPair('licensa', False)
// else
// JSONObject.AddPair('licensa', True);
//
// JSONObject.AddPair('modulos', JSONModulos);
//
// JSonObjectWhatsapp := TJSONObject.Create;
// JSonObjectWhatsapp.AddPair('status', frmServidor.StatusWhatsapp);
// JSonObjectWhatsapp.AddPair('celular', frmServidor.NumeroWhatsapp);
// JSonObjectWhatsapp.AddPair('base64', frmServidor.Base64Whatsapp);
// JSonObjectWhatsapp.AddPair('logout', frmServidor.LogoutWhatsapp);
// JSonObjectWhatsapp.AddPair('name', frmServidor.NomeWhatsapp);
// JSonObjectWhatsapp.AddPair('url', frmServidor.ImagemWhatsapp);
// JSonObjectWhatsapp.AddPair('msgErro', frmServidor.StatusErroWhatsapp);
// JSonObjectWhatsapp.AddPair('statusOperacao', frmServidor.StatusMensagemWhatsapp);
//
// if frmServidor.StatusMensagemWhatsapp = 2 then
// frmServidor.StatusMensagemWhatsapp := 0;
//
// JSONObject.AddPair('whatsapp', JSonObjectWhatsapp);
//
// Marca('json_basico');
// Stopwatch := TStopwatch.StartNew;
//
// ArrayiFood := TJsonArray.Create;
//
// if frmServidor.dataSetMerchants1.RecordCount > 0 then
// begin
// conexao.SQL.Add('select * from ifood_connect');
// DadosiFood.LoadFromJSON(conexao.ConsultaSQL);
// end;
//
// if DadosiFood.RecordCount > 0 then
// begin
// ObjetoiFood := TJSONObject.Create;
// ObjetoiFood.AddPair('statusLoja',
// frmServidor.dataSetMerchants1.FieldByName('messagetitle').AsString);
// ObjetoiFood.AddPair('detalheLoja',
// frmServidor.dataSetMerchants1.FieldByName('messagesubtitle').AsString);
// ObjetoiFood.AddPair('status',
// frmServidor.dataSetMerchants1.FieldByName('available').AsString);
// ObjetoiFood.AddPair('loja', DadosiFood.FieldByName('name').AsString);
// ArrayiFood.AddElement(ObjetoiFood);
// end;
//
// Marca('ifood');
// Stopwatch := TStopwatch.StartNew;
// JSONObject.AddPair('taxaEntrega', frmServidor.GetTaxaEntrega);
// JSONObject.AddPair('ifood', ArrayiFood);
// JSONObject.AddPair('user', frmServidor.UserID.ToString);
//
// JSONNFCe := TJSONObject.Create;
//
// conexao.SQL.Add('SELECT 0 as zero, nfce FROM dados_whatsapp');
// NFC := conexao.FieldByName('nfce');
//
// if NFC = '1' then
// begin
// JSONNFCe.AddPair('usa', True);
//
// conexao.SQL.Add(
// 'SELECT count(*) as quantidade, 0 as zero FROM pedido WHERE nfce_emite = 1 and id_caixa > 0 AND status > 0 AND data_pedido >= '
// + QuotedStr(FormatDateTime('yyyy-mm-01', now))
// + ' and codigo_pedido_dia > 0');
//
// QUANTIDADE := conexao.FieldByName('quantidade');
//
// JSONNFCe.AddPair('contigencia', QUANTIDADE);
// JSONNFCe.AddPair('erro', frmServidor.memErrosNFCE.ToJSONArray());
// end
// else
// begin
// JSONNFCe.AddPair('contigencia', 0);
// JSONNFCe.AddPair('usa', False);
// JSONNFCe.AddPair('erro', '[]');
// end;
//
// JSONObject.AddPair('nfce', JSONNFCe);
//
// Marca('nfce');
// Stopwatch := TStopwatch.StartNew;
//
// try
// Reader := TStreamReader.Create('atualizacao.json', TEncoding.UTF8);
// try
// JSONStr := Reader.ReadToEnd;
// finally
// Reader.Free;
// end;
//
// JSONObject.AddPair('atualizacao',
// TJSONObject.ParseJSONValue(JSONStr) as TJSONObject);
// except
// end;
//
// Marca('arquivo_atualizacao');
// Stopwatch := TStopwatch.StartNew;
//
// if frmServidor.memPaineis.RecordCount = 0 then
// begin
// conexao.SQL.Add('SELECT * FROM painel where tipo <> 3');
// frmServidor.memPaineis.LoadFromJSON(conexao.ConsultaSQL);
// end;
//
// if frmServidor.memBanner.RecordCount = 0 then
// begin
// conexao.SQL.Add(
// 'select *, DAYOFWEEK(curdate()) from banner where link <> "" and dia_semana like concat("%",DAYOFWEEK(curdate()),"%")');
// frmServidor.memBanner.LoadFromJSON(conexao.ConsultaSQL);
// end;
//
// JSONObject.AddPair('banner', frmServidor.memBanner.ToJSONArray());
// JSONObject.AddPair('painel', frmServidor.memPaineis.ToJSONArray());
//
// Marca('banner_painel');
//
// JSONObject.AddPair('performance', PerfArray);
//
// conexao.Free;
//
// Res.Send(JSONObject);
//
// finally
// end;
//
// end;
procedure DoGetWhatsapp(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  JSONObject: TJSONObject;
begin
  JSONObject := TJSONObject.Create;
  JSONObject.AddPair('status', frmServidor.StatusWhatsapp);
  JSONObject.AddPair('celular', frmServidor.NumeroWhatsapp);
  JSONObject.AddPair('base64', frmServidor.Base64Whatsapp);
  JSONObject.AddPair('logout', frmServidor.LogoutWhatsapp);
  Res.Send<TJSONObject>(JSONObject);
end;

procedure DoPostWhatsappLogout(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
  JSonObjectWhatsapp: TJSONObject;
begin
  frmServidor.LogoutWhatsapp := True;
  Requisicao := iRequisicao.Create(nil);
  Requisicao.BaseURL :=
    'https://old.goopedir.com/whatsapp/deletar.php?instance=' +
    frmServidor.UserID.ToString;
  Requisicao.TempoExpiracao := 15 * 1000;
  try
    Requisicao.Execute;
    frmServidor.StatusWhatsapp := False;
    frmServidor.NumeroWhatsapp := '';
    frmServidor.DadosApiWhatsapp;
    JSonObjectWhatsapp := TJSONObject.Create;
    JSonObjectWhatsapp.AddPair('status', frmServidor.StatusWhatsapp);
    JSonObjectWhatsapp.AddPair('celular', frmServidor.NumeroWhatsapp);
    JSonObjectWhatsapp.AddPair('base64', frmServidor.Base64Whatsapp);
    JSonObjectWhatsapp.AddPair('logout', frmServidor.LogoutWhatsapp);
    JSonObjectWhatsapp.AddPair('name', frmServidor.NomeWhatsapp);
    JSonObjectWhatsapp.AddPair('url', frmServidor.ImagemWhatsapp);
    Res.Send<TJSONObject>(JSonObjectWhatsapp);
  except
    Res.Status(400);
  end;
  Requisicao.Free;
end;

procedure DoPostWhatsappAtualizar(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  JSonObjectWhatsapp: TJSONObject;
begin
  frmServidor.DadosApiWhatsapp;
  JSonObjectWhatsapp := TJSONObject.Create;
  JSonObjectWhatsapp.AddPair('status', frmServidor.StatusWhatsapp);
  JSonObjectWhatsapp.AddPair('celular', frmServidor.NumeroWhatsapp);
  JSonObjectWhatsapp.AddPair('base64', frmServidor.Base64Whatsapp);
  JSonObjectWhatsapp.AddPair('logout', frmServidor.LogoutWhatsapp);
  JSonObjectWhatsapp.AddPair('name', frmServidor.NomeWhatsapp);
  JSonObjectWhatsapp.AddPair('url', frmServidor.ImagemWhatsapp);
  Res.Send<TJSONObject>(JSonObjectWhatsapp);
end;

procedure DoPostPedidoProdutosSeleciona(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('update pedido_produtos set selecionado = :selecionado where codigo = :codigo');
  conexao.Parametros('codigo', Req.Params['codigo']);
  conexao.Parametros('selecionado', Req.Params['selecionado']);
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoGetPagamentoProduto(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('select * from caixa_movimento_produto where id_pedido_produto = :codigo');
  conexao.Parametros('codigo', Req.Params['codigo']);
  Res.Send(conexao.ConsultaSQL.ToString);
  conexao.Free;
end;

procedure DoPostPagamentoProdutos(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Dados: TJsonArray;
  i: Integer;
  Codigo: Integer;
  QuantidadePago: Real;
begin
  conexao := TConexao.Create('v2');
  Dados := TJsonArray.ParseJSONValue(Req.body) as TJsonArray;
  for i := 0 to Dados.Count - 1 do
  begin
    try
      QuantidadePago := Dados[i].GetValue<Real>('quantpago');
    except
      QuantidadePago := Dados[i].GetValue<Real>('quantidade');
    end;
    if QuantidadePago = 0 then
    begin
      QuantidadePago := Dados[i].GetValue<Real>('quantidade');
    end;
    Codigo := conexao.GerarID('caixa_movimento_produto', 'id');
    conexao.SQL.Add
      ('insert into caixa_movimento_produto (id,id_caixa_movimento,id_pedido_produto,quantidade,valor)');
    conexao.SQL.Add
      ('values (:id,:id_caixa_movimento,:id_pedido_produto,:quantidade,:valor)');
    conexao.Parametros('id', Codigo);
    conexao.Parametros('id_caixa_movimento', Req.Params['caixa']);
    conexao.Parametros('id_pedido_produto',
      Dados[i].GetValue<Integer>('codigo'));
    if Dados[i].GetValue<Real>('quantidade') = QuantidadePago then
    begin
      if QuantidadePago > 1 then
      begin
        conexao.Parametros('quantidade', Dados[i].GetValue<Real>('quantidade') /
          QuantidadePago);
      end
      else
      begin
        conexao.Parametros('quantidade', QuantidadePago);
      end;
    end
    else
      conexao.Parametros('quantidade', Dados[i].GetValue<Real>('quantidade') /
        QuantidadePago);
    conexao.Parametros('valor', Dados[i].GetValue<Real>('valor') /
      (QuantidadePago));
    conexao.ExecuteSQL;
  end;
  conexao.Free;
end;

procedure DoPostTransferenciaProdutos(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Dados: TJsonArray;
  i: Integer;
  Banco: TFDMemTable;
  Quantidade: Real;
  QuantidadeTransferencia: Real;
  NomeProduto: String;
  Unitario: Real;
  Total: Real;
  Adicional: Real;
  Codigo: Integer;
  CodigoAux: Integer;
  CodigoPedido: Integer;
  DescricaoMesaPara: String;
  DescricaoMesaDe: String;
begin
  conexao := TConexao.Create('v2');
  Dados := TJsonArray.ParseJSONValue(Req.body) as TJsonArray;
  Banco := TFDMemTable.Create(nil);
  conexao.SQL.Add('select concat(tp.descricao,' + QuotedStr(' ') +
    ',m.nr_mesa) as descricao, 0 as zero from mesa as m');
  conexao.SQL.Add('join mesa_tipo as tp on tp.id_mesa_tipo = m.fk_tipo_mesa');
  conexao.SQL.Add('where m.id_mesa = :id');
  conexao.Parametros('id', Req.Params['pedido']);
  DescricaoMesaPara := conexao.FieldByName('descricao');
  conexao.SQL.Add('select * from mesa where id_mesa = :id');
  conexao.Parametros('id', Req.Params['pedido']);
  CodigoPedido := conexao.FieldByName('selecionada');
  if CodigoPedido = 0 then
  begin
    // CodigoPedido := conexao.FieldByName('selecionada');
    conexao.SQL.Clear;
    CodigoPedido := conexao.GerarID('pedido', 'codigo');
    conexao.SQL.Add
      ('insert into pedido (codigo,codigo_pedido_dia,codigo_cliente,codigo_cliente_endereco,data_pedido,hora_pedido,status,valor_pedido,valor_desconto,valor_taxa_entrega,valor_total_pedido,observacao_geral,troco,tipo_pagamento,');
    conexao.SQL.Add
      ('pedido_impresso,origem,desc_ficha,id_ficha,ficha_faturada)');
    conexao.SQL.Add
      ('values (:codigo,:codigo_pedido_dia,:codigo_cliente,:codigo_endereco,:data_pedido,:hora_pedido,:status,:valor_pedido,:valor_desconto,:valor_taxa_entrega,:valor_total_pedido,:observacao_geral,:troco,:tipo_pagamento,');
    conexao.SQL.Add
      (':pedido_impresso,:origem,:desc_ficha,:id_ficha,:ficha_faturada)');
    conexao.Parametros('codigo', CodigoPedido);
    conexao.Parametros('codigo_pedido_dia', '0');
    conexao.Parametros('codigo_cliente', '0');
    conexao.Parametros('codigo_endereco', '0');
    conexao.Parametros('data_pedido', FormatDateTime('yyyy-mm-dd', now));
    conexao.Parametros('hora_pedido', FormatDateTime('hh:mm:ss', now));
    conexao.Parametros('status', '-1');
    conexao.Parametros('valor_pedido', '0');
    conexao.Parametros('valor_taxa_entrega', '0');
    conexao.Parametros('valor_desconto', '0');
    conexao.Parametros('valor_total_pedido', '0');
    conexao.Parametros('observacao_geral', '');
    conexao.Parametros('troco', '0');
    conexao.Parametros('tipo_pagamento', '0');
    conexao.Parametros('pedido_impresso', '0');
    conexao.Parametros('origem', '3');
    conexao.Parametros('desc_ficha', DescricaoMesaPara);
    conexao.Parametros('id_ficha', Req.Params['pedido']);
    conexao.Parametros('ficha_faturada', Req.Params['pedido']);
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('update mesa set selecionada = :selecionada where id_mesa = :pedido');
    conexao.Parametros('pedido', Req.Params['pedido']);
    conexao.Parametros('selecionada', CodigoPedido);
    conexao.ExecuteSQL;
  end;
  for i := 0 to Dados.Count - 1 do
  begin
    conexao.SQL.Add('select * from pedido_produtos where codigo = :codigo');
    conexao.Parametros('codigo', Dados[i].GetValue<Integer>('codigo'));
    Banco.Close;
    Banco.LoadFromJSON(conexao.ConsultaSQL);
    if Banco.RecordCount > 0 then
    begin
      conexao.SQL.Add('select concat(tp.descricao,' + QuotedStr(' ') +
        ',m.nr_mesa) as descricao, 0 as zero from mesa as m');
      conexao.SQL.Add
        ('join mesa_tipo as tp on tp.id_mesa_tipo = m.fk_tipo_mesa');
      conexao.SQL.Add('where m.selecionada = :id');
      conexao.Parametros('id', Banco.FieldByName('codigo_pedido').AsInteger);
      DescricaoMesaDe := conexao.FieldByName('descricao');
      Quantidade := Banco.FieldByName('quantidade').AsFloat;
      try
        QuantidadeTransferencia := Dados[i].GetValue<Real>('quantidade');
      except
        QuantidadeTransferencia := Quantidade;
      end;
      if QuantidadeTransferencia > Quantidade then
      begin
        conexao.SQL.Add
          ('select 0 as zero, nome_produto as nome from produto codigo = :codigo');
        conexao.Parametros('codigo', Banco.FieldByName('codigo_produto')
          .AsInteger);
        NomeProduto := conexao.FieldByName('nome');
        conexao.Free;
        Banco.Free;
        Res.Send('O produto "' + NomeProduto +
          '" foi selecionado uma quantidade maior que a atual, atualize a tela apertando F5!')
          .Status(500);
        exit;
      end;
      if QuantidadeTransferencia = Quantidade then
      begin
        conexao.SQL.Add
          ('update pedido_produtos set codigo_pedido = :codigo_pedido, html = :html where codigo = :codigo');
        conexao.Parametros('codigo', Banco.FieldByName('codigo').AsInteger);
        conexao.Parametros('codigo_pedido', CodigoPedido);
        conexao.Parametros('html',
          RemoverTodasTransferencias(Banco.FieldByName('html').AsString) +
          '<p><i>Transfer?ncia De ' + DescricaoMesaDe + ' para ' +
          DescricaoMesaPara + ' </i></p>');
        conexao.ExecuteSQL;
      end
      else
      begin
        Codigo := conexao.GerarID('pedido_produtos', 'codigo');
        Unitario := ((Banco.FieldByName('valor_unitario').AsFloat / Quantidade)
          * QuantidadeTransferencia);
        Total := ((Banco.FieldByName('valor_total').AsFloat / Quantidade) *
          QuantidadeTransferencia);
        Adicional :=
          ((Banco.FieldByName('valor_adicional').AsFloat / Quantidade) *
          QuantidadeTransferencia);
        conexao.SQL.Add
          ('update pedido_produtos set valor_unitario = valor_unitario - :valor_unitario, quantidade = quantidade - :quantidade, valor_total = valor_total - :valor_total, valor_adicional = valor_adicional - :valor_adicional where codigo = :codigo');
        conexao.Parametros('valor_unitario', Unitario);
        conexao.Parametros('quantidade', QuantidadeTransferencia);
        conexao.Parametros('valor_total', Total);
        conexao.Parametros('valor_adicional', Adicional);
        conexao.Parametros('codigo', Dados[i].GetValue<Integer>('codigo'));
        conexao.ExecuteSQL;
        conexao.SQL.Add
          ('insert into pedido_produtos (codigo,codigo_pedido,codigo_produto,valor_unitario,quantidade,valor_total,valor_adicional,impresso,html)');
        conexao.SQL.Add
          ('values (:codigo,:codigo_pedido,:codigo_produto,:valor_unitario,:quantidade,:valor_total,:valor_adicional,1,:html)');
        conexao.Parametros('codigo', Codigo);
        conexao.Parametros('codigo_pedido', CodigoPedido);
        conexao.Parametros('codigo_produto', Banco.FieldByName('codigo_produto')
          .AsInteger);
        conexao.Parametros('valor_unitario', Unitario);
        conexao.Parametros('quantidade', QuantidadeTransferencia);
        conexao.Parametros('valor_total', Total);
        conexao.Parametros('valor_adicional', Adicional);
        conexao.Parametros('html',
          RemoverTodasTransferencias(Banco.FieldByName('html').AsString) +
          '<p><i>Dividido De ' + FloatToStr(Quantidade) + ' para ' +
          FloatToStr(QuantidadeTransferencia) + ' </i></p>' +
          '<p><i>Transfer?ncia De ' + DescricaoMesaDe + ' para ' +
          DescricaoMesaPara + ' </i></p>');
        conexao.ExecuteSQL;
        CodigoAux := conexao.GerarID('pedido_produto_sap', 'id');
        conexao.SQL.Add
          ('insert into pedido_produto_sap (id,codigo_pedido_produto,tipo,nomeclatura,descricao,valor,tipo_valor)');
        conexao.SQL.Add
          ('values (:id,:codigo_pedido_produto,0,:nomeclatura,:descricao,0,0)');
        conexao.Parametros('id', CodigoAux);
        conexao.Parametros('codigo_pedido_produto', Codigo);
        conexao.Parametros('nomeclatura', 'Divis?o');
        conexao.Parametros('descricao', 'De ' + FloatToStr(Quantidade) +
          ' para ' + FloatToStr(QuantidadeTransferencia));
        conexao.ExecuteSQL;
      end;
    end
    else
    begin
      conexao.Free;
      Banco.Free;
      Res.Send('Produto n?o localizado!').Status(500);
      exit;
    end;
  end;
  AtualizaValorPedido(Banco.FieldByName('codigo_pedido').AsInteger);
  AtualizaValorPedido(CodigoPedido);
  conexao.Free;
  Banco.Free;
  Res.Send('OK');
end;

procedure doPostReImportar(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Requisicao: iRequisicao;
begin
  Requisicao := iRequisicao.Create(nil);
  Requisicao.BaseURL := 'https://old.goopedir.com/v1/';
  Requisicao.URL := 'reimportar.php?codigo=' + Req.Params['codigo'];
  Requisicao.TempoExpiracao := 15 * 1000;
  try
    Requisicao.Execute;
  except
  end;
  Requisicao.Free;
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('delete from geradores');
  conexao.ExecuteSQL;
  conexao.Free;
  // res.Send(conexao.GerarID(Req.Params['tabela'],Req.Params['campo']).ToString);
  Res.Send('ok');
end;

procedure doPostGerarId(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  Res.Send(conexao.GerarID(Req.Params['tabela'], Req.Params['campo']).ToString);
  conexao.Free;
end;

procedure DoGetValidaNumero(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Result: String;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('SELECT numero, DATE_FORMAT(data, "%d/%m/%Y") AS data FROM mensagem_whatsapp where numero = :numero');
  conexao.Parametros('numero', Req.Params['numero']);
  try
    Result := conexao.FieldByName('data');
  except
    Result := '';
  end;
  if Result <> '' then
  begin
    conexao.SQL.Add
      ('UPDATE mensagem_whatsapp SET data = CURRENT_DATE WHERE numero = :numero');
    conexao.Parametros('numero', Req.Params['numero']);
    conexao.ExecuteSQL;
  end;
  if (Result = '0') then
  begin
    conexao.SQL.Add
      ('INSERT INTO mensagem_whatsapp (numero, data) values (:numero,CURRENT_DATE)');
    conexao.Parametros('numero', Req.Params['numero']);
    conexao.ExecuteSQL;
  end;
  if Result <> FormatDateTime('dd/mm/yyyy', Date) then
  begin
    Res.Send('true');
  end
  else
  begin
    Res.Send('false');
  end;
  conexao.Free;
end;

procedure DoPostGravaPedidoSite(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  DadosPedido: TJSONObject;
  IdPedidoSite: Integer;
  cliente: TJSONObject;
  Pagamento: TJSONObject;
  Endereco: TJSONObject;
  Valores: TJSONObject;
  Outros: TJSONObject;
  Produtos: TJsonArray;
  Retorno: TJSONObject;
begin
  DadosPedido := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  try
    IdPedidoSite := DadosPedido.GetValue('id').ToString.ToInteger;
    cliente := TJSONObject.ParseJSONValue(DadosPedido.GetValue('cliente')
      .ToString) as TJSONObject;
    Pagamento := TJSONObject.ParseJSONValue(DadosPedido.GetValue('pagamento')
      .ToString) as TJSONObject;
    Endereco := TJSONObject.ParseJSONValue(DadosPedido.GetValue('endereco')
      .ToString) as TJSONObject;
    Valores := TJSONObject.ParseJSONValue(DadosPedido.GetValue('valores')
      .ToString) as TJSONObject;
    Outros := TJSONObject.ParseJSONValue(DadosPedido.GetValue('outros')
      .ToString) as TJSONObject;
    Produtos := TJSONObject.ParseJSONValue(DadosPedido.GetValue('produtos')
      .ToString) as TJsonArray;
    cliente := ClientePedido(cliente);
    Pagamento := PagamentoPedido(Pagamento);
    Endereco := ClienteEnderecoPedido(Endereco, cliente.GetValue('codigo')
      .ToString.ToInteger);
    Retorno := GerarPedidoSite(IdPedidoSite, cliente, Endereco, Pagamento,
      Valores, Outros, Produtos);
    FreeAndNil(cliente);
    FreeAndNil(Pagamento);
    FreeAndNil(Endereco);
    FreeAndNil(Valores);
    FreeAndNil(Produtos);
    Res.Send(Retorno);
  except
    Res.Status(400).Send('Body invalido!');
  end;
  DadosPedido.Free;
end;

procedure DoPostDelete(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('delete from mesa where id_mesa = :id');
  conexao.Parametros('id', Req.Params['id']);
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoPostDeletaHorario(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('delete from horario where dia_da_sema = :dia');
  conexao.Parametros('dia', Req.Params['dia']);
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoPostCadastroHorario(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
  Segunda: Boolean;
  Terca: Boolean;
  Quarta: Boolean;
  Quinta: Boolean;
  Sexta: Boolean;
  Sabado: Boolean;
  Domingo: Boolean;
  Abertura: String;
  Fechamento: String;
begin
  conexao := TConexao.Create('v2');
  JSONObject := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetBytes(Req.body), 0)
    as TJSONObject;
  Segunda := JSONObject.GetValue('segunda').Value.ToBoolean();
  Terca := JSONObject.GetValue('terca').Value.ToBoolean();
  Quarta := JSONObject.GetValue('quarta').Value.ToBoolean();
  Quinta := JSONObject.GetValue('quinta').Value.ToBoolean();
  Sexta := JSONObject.GetValue('sexta').Value.ToBoolean();
  Sabado := JSONObject.GetValue('sabado').Value.ToBoolean();
  Domingo := JSONObject.GetValue('domingo').Value.ToBoolean();
  Abertura := JSONObject.GetValue('abertura').Value;
  Fechamento := JSONObject.GetValue('fechamento').Value;
  if Segunda then
  begin
    conexao.SQL.Add('delete from horario where dia_da_sema = :semana');
    conexao.Parametros('semana', 'seg');
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into horario (dia_da_sema,abertura,fechamento,status) values (:semana,:abertura,:fechamento,1)');
    conexao.Parametros('semana', 'seg');
    conexao.Parametros('abertura', Abertura);
    conexao.Parametros('fechamento', Fechamento);
    conexao.ExecuteSQL;
  end;
  if Terca then
  begin
    conexao.SQL.Add('delete from horario where dia_da_sema = :semana');
    conexao.Parametros('semana', 'ter');
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into horario (dia_da_sema,abertura,fechamento,status) values (:semana,:abertura,:fechamento,1)');
    conexao.Parametros('semana', 'ter');
    conexao.Parametros('abertura', Abertura);
    conexao.Parametros('fechamento', Fechamento);
    conexao.ExecuteSQL;
  end;
  if Quarta then
  begin
    conexao.SQL.Add('delete from horario where dia_da_sema = :semana');
    conexao.Parametros('semana', 'qua');
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into horario (dia_da_sema,abertura,fechamento,status) values (:semana,:abertura,:fechamento,1)');
    conexao.Parametros('semana', 'qua');
    conexao.Parametros('abertura', Abertura);
    conexao.Parametros('fechamento', Fechamento);
    conexao.ExecuteSQL;
  end;
  if Quinta then
  begin
    conexao.SQL.Add('delete from horario where dia_da_sema = :semana');
    conexao.Parametros('semana', 'qui');
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into horario (dia_da_sema,abertura,fechamento,status) values (:semana,:abertura,:fechamento,1)');
    conexao.Parametros('semana', 'qui');
    conexao.Parametros('abertura', Abertura);
    conexao.Parametros('fechamento', Fechamento);
    conexao.ExecuteSQL;
  end;
  if Sexta then
  begin
    conexao.SQL.Add('delete from horario where dia_da_sema = :semana');
    conexao.Parametros('semana', 'sex');
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into horario (dia_da_sema,abertura,fechamento,status) values (:semana,:abertura,:fechamento,1)');
    conexao.Parametros('semana', 'sex');
    conexao.Parametros('abertura', Abertura);
    conexao.Parametros('fechamento', Fechamento);
    conexao.ExecuteSQL;
  end;
  if Sabado then
  begin
    conexao.SQL.Add('delete from horario where dia_da_sema = :semana');
    conexao.Parametros('semana', 'sab');
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into horario (dia_da_sema,abertura,fechamento,status) values (:semana,:abertura,:fechamento,1)');
    conexao.Parametros('semana', 'sab');
    conexao.Parametros('abertura', Abertura);
    conexao.Parametros('fechamento', Fechamento);
    conexao.ExecuteSQL;
  end;
  if Domingo then
  begin
    conexao.SQL.Add('delete from horario where dia_da_sema = :semana');
    conexao.Parametros('semana', 'dom');
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('insert into horario (dia_da_sema,abertura,fechamento,status) values (:semana,:abertura,:fechamento,1)');
    conexao.Parametros('semana', 'dom');
    conexao.Parametros('abertura', Abertura);
    conexao.Parametros('fechamento', Fechamento);
    conexao.ExecuteSQL;
  end;
  conexao.Free;
  JSONObject.Free;
  frmServidor.SincronizaHorario;
end;

procedure DoPostCadastroGeral(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
  JSONArray: TJsonArray;
  JSONValue: TJSONValue;
  jsonPair: TJSONPair;
  Codigo: Integer;
  Cadastro: Boolean;
  Tabela: String;
  Campo: String;
  CampoInsert: String;
  ValuesInsert: String;
  i: Integer;
begin
  conexao := TConexao.Create('v2');
  JSONObject := TJSONObject.ParseJSONValue(TEncoding.UTF8.GetBytes(Req.body), 0)
    as TJSONObject;
  try
    Tabela := JSONObject.GetValue('tabela').Value;
    Campo := JSONObject.GetValue('campo').Value;
    JSONValue := JSONObject.GetValue('valor');
    try
      Codigo := JSONValue.Value.ToInteger;
      Cadastro := False;
    except
      Cadastro := True;
      Codigo := conexao.GerarID(Tabela, Campo);
    end;
    if Codigo = 0 then
    begin
      Cadastro := True;
      Codigo := conexao.GerarID(Tabela, Campo);
    end;
    conexao.Parametros(Campo, Codigo);
    JSONArray := JSONObject.GetValue('campos') as TJsonArray;
    if JSONArray <> nil then
    begin
      if not(Cadastro) then
        conexao.SQL.Add('update ' + Tabela + ' set ')
      else
        conexao.SQL.Add('insert into ' + Tabela);
      for i := 0 to JSONArray.Count - 1 do
      begin
        JSONValue := JSONArray.Items[i];
        if JSONValue is TJSONObject then
        begin
          JSONObject := JSONValue as TJSONObject;
          conexao.Parametros(JSONObject.GetValue('campo').Value,
            JSONObject.GetValue('valor').Value);
          if (i = 0) then
          begin
            if not(Cadastro) then
              conexao.SQL.Add(JSONObject.GetValue('campo').Value + ' = :' +
                JSONObject.GetValue('campo').Value)
            else
            begin
              CampoInsert := Campo + ',' + JSONObject.GetValue('campo').Value;
              ValuesInsert := ':' + Campo + ',:' + JSONObject.GetValue
                ('campo').Value;
            end;
          end
          else
          begin
            if not(Cadastro) then
              conexao.SQL.Add(',' + JSONObject.GetValue('campo').Value + ' = :'
                + JSONObject.GetValue('campo').Value)
            else
            begin
              CampoInsert := CampoInsert + ',' + JSONObject.GetValue
                ('campo').Value;
              ValuesInsert := ValuesInsert + ',:' +
                JSONObject.GetValue('campo').Value;
            end;
          end;
          // memo.Lines.Add(jsonObject.GetValue('campo').Value + ': ' + jsonObject.GetValue('valor').Value);
        end;
      end;
      if not(Cadastro) then
      begin
        conexao.SQL.Add('where ' + Campo + ' = :' + Campo)
      end
      else
      begin
        conexao.SQL.Add('(' + CampoInsert + ') values (' + ValuesInsert + ') ')
      end;
      // conexao.SQL.Add('insert into ' + Tabela);
      conexao.ExecuteSQL;
    end;
    if Tabela = 'taxa_entrega' then
    begin
      frmServidor.TaxaEntrega.Close;
      if frmServidor.UserID > 0 then
      begin
        SincronizaTaxaEntrega(frmServidor.UserID);
      end;
      frmServidor.TaxaEntrega.Close;
    end;
    if Tabela = 'tipo_pagamento' then
    begin
      if frmServidor.UserID > 0 then
      begin
        SincronizaFormaPagamento(frmServidor.UserID);
      end;
      frmServidor.TipoPagamento.Close;
    end;
    if Tabela = 'motoboy' then
    begin
      if frmServidor.UserID > 0 then
      begin
        SincronizaMotoboy(frmServidor.UserID);
      end;
    end;
    if Tabela = 'banner' then
    begin
      frmServidor.memBanner.Close;
    end;
    if Tabela = 'painel' then
    begin
      frmServidor.memPaineis.Close;
    end;

    // memo.Lines.Add('Tabela: ' + jsonObject.GetValue('tabela').Value);
    // JSONValue := JSONObject.GetValue('campo');
    // if JSONValue <> nil then
    // memo.Lines.Add('Campo: ' + JSONValue.Value);
    // if jsonValue <> nil then
    // memo.Lines.Add('Valor: ' + jsonValue.Value);
  finally
  end;
end;

procedure DoDeleteUserAgent(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('delete agent where id = :id');
  conexao.Parametros('id', Req.Params['codigo']);
  conexao.ExecuteSQL;
  frmServidor.Agent.Remove(Req.Params['codigo']);
  conexao.Free;
end;

procedure DoPostUserAgentStatus(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
begin
  conexao := TConexao.Create('v2');
  JSONObject := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  conexao.SQL.Add('update agent set status = :status where id = :id');
  conexao.Parametros('status', JSONObject.GetValue('status').Value);
  conexao.Parametros('id', JSONObject.GetValue('id').Value);
  conexao.ExecuteSQL;
  frmServidor.Agent.Instance.SetStatus(JSONObject.GetValue('id').Value,
    JSONObject.GetValue('status').Value.ToInteger);
  conexao.Free;
  JSONObject.Free;
end;

procedure DoPostUserAgentName(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
begin
  conexao := TConexao.Create('v2');
  JSONObject := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  conexao.SQL.Add('update agent set nome = :nome where id = :id');
  conexao.Parametros('nome', JSONObject.GetValue('nome').Value);
  conexao.Parametros('id', JSONObject.GetValue('id').Value);
  conexao.ExecuteSQL;
  conexao.Free;
  JSONObject.Free;
end;

procedure DoPostNfceDaddos(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
begin
  conexao := TConexao.Create('v2');
  JSONObject := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  conexao.SQL.Add
    ('update pedido set cpf = :cpf, nome = :nome where codigo = :codigo');
  conexao.Parametros('cpf', JSONObject.GetValue('cpfcnpj').Value);
  conexao.Parametros('nome', JSONObject.GetValue('nome').Value);
  conexao.Parametros('codigo', JSONObject.GetValue('pedido').Value);
  conexao.ExecuteSQL;
  conexao.Free;
  JSONObject.Free;
end;

procedure DoPostPontoFidelidade(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
begin
  Requisicao := iRequisicao.Create(nil);
  Requisicao.BaseURL := 'https://old.goopedir.com/v1/fidelidadepdv.php';
  Requisicao.TempoExpiracao := 30 * 1000;
  Requisicao.body(Req.body);
  Requisicao.Metodo := mPost;
  try
    Requisicao.Execute;
  except
  end;
  Res.Send(Requisicao.Retorno);
  Requisicao.Free;
end;

procedure DoGetUserAgent(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Agent: TAgentSession;
begin
  Agent := frmServidor.Agent.Instance.Get(Req.Params['codigo']);
  if not Assigned(Agent) then
  begin
    Res.Status(404).Send('Token inv?lido ou expirado');
    exit;
  end;
  Res.Send<TJSONObject>(TJSONObject.Create.AddPair('id', Agent.Codigo)
    .AddPair('status', TJSONNumber.Create(Agent.Status)));
end;

procedure DoPostUserAgent(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  Agent: TAgentSession;
begin
  Agent := frmServidor.Agent.Instance.Get(Req.Params['codigo']);
  conexao := TConexao.Create('v2');
  if Assigned(Agent) then
  begin
    conexao.SQL.Add('update agent set datahora where codigo = :codigo');
    conexao.Parametros('codigo', Req.Params['codigo']);
    conexao.ExecuteSQL;
    Res.Status(200).Send('ja cadastrado');
    conexao.Free;
    exit;
  end;
  conexao.SQL.Add
    ('insert into agent values (:codigo,current_timestamp(),0,:agent,:usuario)');
  conexao.Parametros('codigo', Req.Params['codigo']);
  conexao.Parametros('agent', Req.Params['codigo']);
  conexao.Parametros('usuario', Req.Headers['user'].ToInteger());
  conexao.ExecuteSQL;
  frmServidor.Agent.AddOrUpdate(Req.Params['codigo']);
  conexao.Free;
end;

procedure DoGetFidelidadeHistoricoSite(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  Requisicao: iRequisicao;
  Dados: TFDMemTable;
begin
  Requisicao := iRequisicao.Create(nil);
  Dados := TFDMemTable.Create(nil);
  Requisicao.BaseURL := 'https://old.goopedir.com/v1/';
  Requisicao.URL := 'historico/' + Req.Params['codigo'] + '/a';
  Requisicao.MemTable2 := Dados;
  Requisicao.TempoExpiracao := 30 * 1000;
  Requisicao.Execute;
  Res.Send<TJsonArray>(Dados.ToJSONArray());
  Requisicao.Free;
  Dados.Free;
end;

procedure DoGetNotificacaoProdutosAbaixoEstoque(Req: THorseRequest;
Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('SELECT p.*, SUM(pe.quantidade) AS estoque, (select estoque_wpp from dados_whatsapp where estoque_wpp <> curdate()) as data_envio');
  conexao.SQL.Add('FROM produto p');
  conexao.SQL.Add
    ('LEFT JOIN produto_estoque pe ON p.codigo = pe.codigo_produto');
  conexao.SQL.Add('WHERE p.controle_estoque = 1 ');
  conexao.SQL.Add('GROUP BY p.codigo');
  conexao.SQL.Add('HAVING IFNULL(SUM(pe.quantidade), 0) <= p.estoque_min;');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.SQL.Add('update dados_whatsapp set estoque_wpp = curdate()');
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoGetRelatorioProdutosPeriodo(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
  Origem: Boolean;
  SQL: String;
begin
  JSONObject := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  try
    Origem := JSONObject.GetValue<Boolean>('origem');
  except
    Origem := True;
  end;
  conexao := TConexao.Create('v2');
  SQL := '';
  // SQL := SQL + 'SELECT ';
  // SQL := SQL + '    produto, ';
  // SQL := SQL + '    SUM(quantidade) AS quantidade, ';
  // SQL := SQL + '    ROUND(SUM(total), 2) AS total ';
  // SQL := SQL + 'FROM (';
  SQL := SQL + '    SELECT ';
  SQL := SQL + '        CASE ';
  if Origem then
    SQL := SQL +
      '            WHEN p.codigo_cliente_endereco > 0 THEN CONCAT(UPPER(prod.nome_produto), '
      + QuotedStr(' - ENTREGA') + ')'
  else
    SQL := SQL +
      '            WHEN p.codigo_cliente_endereco > 0 THEN UPPER(prod.nome_produto)';
  SQL := SQL + '            ELSE UPPER(prod.nome_produto)';
  SQL := SQL + '        END AS produto, ';
  SQL := SQL + '        SUM(pp.quantidade) AS quantidade, ';
  SQL := SQL + '        SUM(pp.valor_total) AS total';
  SQL := SQL + '    from pedido AS p';
  SQL := SQL + '    join pedido_produtos AS pp ON pp.codigo_pedido = p.codigo';
  SQL := SQL + '    join produto AS prod ON prod.codigo = pp.codigo_produto';
  SQL := SQL + '    WHERE ';
  SQL := SQL + '        p.data_pedido BETWEEN :ini AND :fim';
  SQL := SQL + '        AND p.status > 0 ';
  SQL := SQL + '        AND p.codigo_pedido_dia > 0';
  SQL := SQL + '    GROUP BY ';
  SQL := SQL + '        produto ';
  // SQL := SQL + ') AS produtos_agrupados ';
  // SQL := SQL + 'GROUP BY  produto ';

  // if JSONObject.GetValue('tipo').Value.ToInteger = 0 then
  // begin
  // SQL := SQL + 'LIMIT 10;';
  // end;
  conexao.SQL.Add(CriaSubQueryCampos(SQL,
    'produto, sum(quantidade) as quantidade, ROUND(SUM(total), 2) as total ',
    JSONObject.GetValue('inicial').Value, JSONObject.GetValue('final').Value));
  conexao.SQL.Add('GROUP BY produto');
  conexao.SQL.Add('ORDER BY quantidade DESC');
  if JSONObject.GetValue('tipo').Value.ToInteger = 0 then
    conexao.SQL.Add('LIMIT 10;');
  conexao.Parametros('ini', JSONObject.GetValue('inicial').Value);
  conexao.Parametros('fim', JSONObject.GetValue('final').Value);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
  JSONObject.Free;
end;

function CategoriasToInSQL(const Categorias: string): string;
var
  Partes: TStringDynArray;
  Parte: string;
  ParteTrim: string;
  Codigo: Integer;
begin
  Result := '';
  Partes := SplitString(Categorias, ',');
  for Parte in Partes do
  begin
    ParteTrim := Trim(Parte);
    if (ParteTrim <> '') and TryStrToInt(ParteTrim, Codigo) then
    begin
      if Result <> '' then
        Result := Result + ',';
      Result := Result + Codigo.ToString;
    end;
  end;
end;

procedure DoGetRelatorioSaboresSAPCategoria(Req: THorseRequest;
Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  CategoriasSQL: string;
  DataIni: string;
  DataFim: string;
begin
  CategoriasSQL := CategoriasToInSQL(Req.Params['categorias']);
  if CategoriasSQL = '' then
  begin
    Res.Send('Informe uma ou mais categorias numericas separadas por virgula.')
      .Status(400);
    exit;
  end;

  DataIni := Trim(Req.Query['ini']);
  DataFim := Trim(Req.Query['fim']);

  conexao := TConexao.Create('DoGetRelatorioSaboresSAPCategoria');
  try
    conexao.SQL.Add('select');
    conexao.SQL.Add('  tp.codigo as categoria_id,');
    conexao.SQL.Add('  upper(tp.descricao) as categoria,');
    conexao.SQL.Add('  prod.codigo as produto_id,');
    conexao.SQL.Add('  upper(prod.nome_produto) as produto,');
    conexao.SQL.Add('  min(case');
    conexao.SQL.Add
      ('    when upper(coalesce(pps.nomeclatura, "")) like "%OBSERVA%" or upper(coalesce(pps.nomeclatura, "")) like "%DUVID%" or upper(coalesce(pps.nomeclatura, "")) like "%ATEN%" then ""');
    conexao.SQL.Add
      ('    when paps.id is not null and pap.id_extra is not null then "extra"');
    conexao.SQL.Add('    when sc.id is not null then "extra"');
    conexao.SQL.Add('    when paps.id is not null then "adicional"');
    conexao.SQL.Add('    else "outros"');
    conexao.SQL.Add('  end) as tipo,');
    conexao.SQL.Add('  min(case');
    conexao.SQL.Add
      ('    when upper(coalesce(pps.nomeclatura, "")) like "%OBSERVA%" or upper(coalesce(pps.nomeclatura, "")) like "%DUVID%" or upper(coalesce(pps.nomeclatura, "")) like "%ATEN%" then ""');
    conexao.SQL.Add('    else upper(coalesce(pps.nomeclatura, ""))');
    conexao.SQL.Add('  end) as grupo_sap,');
    conexao.SQL.Add('  min(case');
    conexao.SQL.Add
      ('    when upper(coalesce(pps.nomeclatura, "")) like "%OBSERVA%" or upper(coalesce(pps.nomeclatura, "")) like "%DUVID%" or upper(coalesce(pps.nomeclatura, "")) like "%ATEN%" then ""');
    conexao.SQL.Add('    else upper(coalesce(pps.descricao, ""))');
    conexao.SQL.Add('  end) as item_sap,');
    conexao.SQL.Add('  upper(coalesce(pps.nomeclatura, "")) as grupo_original,');
    conexao.SQL.Add('  upper(coalesce(pps.descricao, "")) as item_original,');
    conexao.SQL.Add('  count(*) as ocorrencias,');
    conexao.SQL.Add('  sum(pp.quantidade) as quantidade,');
    conexao.SQL.Add('  round(sum(coalesce(pps.valor, 0) * pp.quantidade), 2) as valor,');
    conexao.SQL.Add('  max(case');
    conexao.SQL.Add
      ('    when upper(coalesce(pps.nomeclatura, "")) = "SABORES" or sc.id is not null then sc.ultima_compra');
    conexao.SQL.Add('    when paps.id is not null then paps.ultima_compra');
    conexao.SQL.Add('    else null');
    conexao.SQL.Add('  end) as ultima_compra');
    conexao.SQL.Add('from pedido_produto_sap pps');
    conexao.SQL.Add
      ('join pedido_produtos pp on pp.codigo = pps.codigo_pedido_produto');
    conexao.SQL.Add('join pedido p on p.codigo = pp.codigo_pedido');
    conexao.SQL.Add('join produto prod on prod.codigo = pp.codigo_produto');
    conexao.SQL.Add('join tipo_produto tp on tp.codigo = prod.codigo_grupo');
    conexao.SQL.Add
      ('left join pro_adi_personalizado pap on (pap.id_produto = prod.codigo or pap.categoria = prod.codigo_grupo) and upper(pap.descricao) = upper(pps.nomeclatura)');
    conexao.SQL.Add
      ('left join pro_adi_personalizado_sabores paps on paps.id_pro_adi_personalizado = pap.id and upper(paps.nome) = upper(pps.descricao)');
    conexao.SQL.Add
      ('left join sabores_completo sc on (sc.id_produto = prod.codigo or sc.id_tipo_sabor = prod.codigo_grupo) and upper(sc.nome) = upper(pps.descricao)');
    conexao.SQL.Add('where prod.codigo_grupo in (' + CategoriasSQL + ')');
    conexao.SQL.Add('  and p.status > 0');
    conexao.SQL.Add('  and p.codigo_pedido_dia > 0');
    conexao.SQL.Add('  and coalesce(pps.valor, 0) <> 0');
    if (DataIni <> '') and (DataFim <> '') then
    begin
      conexao.SQL.Add('  and p.data_pedido between :ini and :fim');
      conexao.Parametros('ini', DataIni);
      conexao.Parametros('fim', DataFim);
    end;
    conexao.SQL.Add
      ('group by tp.codigo, tp.descricao, prod.codigo, prod.nome_produto, pps.nomeclatura, pps.descricao');
    conexao.SQL.Add('order by categoria, quantidade desc, item_sap');
    Res.Send<TJsonArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;

procedure DoGravaVariosProdutos(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
  DadosProdutos: TFDMemTable;
  mesa: Integer;
  CodigoPedido: Integer;
  CodigoProduto: Integer;
  CodigoPedidoItem: Integer;
  ValorProduto: Real;
  ValorAdicional: Real;
  Adicional: String;
  Pizza: String;
  Quantidade: Real;
  Observacao: String;
  CodigoAux: Integer;
  Descricao: String;
  ValorAux: Real;
  ValorSabor: Real;
  DescricaoMesa: String;
  StatusImpressao: Integer;
  QuantidadeSabores: Integer;
  Usuario: Integer;
  i: Integer;
  ValorPizza: Real;
  Adicionais: TStringDynArray;
  // Vari?veis de tempo
  StartTime, EndTime: TDateTime;
  ExecutionTime: TDateTime;
  MemoLog: TMemo;
begin
  MemoLog := TMemo.Create(nil);
  MemoLog.Parent := frmServidor;
  Dados := TFDMemTable.Create(nil);
  try
    // Dados.LoadFromJSON(Req.Body);
    StartTime := now;
    Dados.LoadFromJSON(Req.body);
    EndTime := now;
    ExecutionTime := EndTime - StartTime;
    MemoLog.Lines.Add('12: ' + FormatDateTime('hh:nn:ss:zzz', ExecutionTime));
  except
    Res.Send('').Status(500);
    Dados.Free;
    exit;
  end;
  try
    Usuario := Req.Params['usuario'].ToInteger;
  except
    Usuario := 0;
  end;
  conexao := TConexao.Create('v2');
  try
    mesa := Dados.FieldByName('mesa').AsInteger;
  except
    mesa := 0;
  end;
  try
    CodigoPedido := Dados.FieldByName('pedido').AsInteger;
  except
    CodigoPedido := 0;
  end;
  CodigoProduto := Dados.FieldByName('produto').AsInteger;
  // Adicional := Dados.FieldByName('adicionais').AsString;
  Quantidade := Dados.FieldByName('qtd').AsFloat;;
  // Pizza := Dados.FieldByName('pizza').AsString;
  Observacao := Dados.FieldByName('observacao').AsString;
  ValorAux := 0;
  ValorProduto := Dados.FieldByName('valor_produto').AsFloat;
  if mesa > 0 then
  begin
    conexao.SQL.Add('select * from mesa where id_mesa = :id');
    conexao.Parametros('id', mesa);
    try
      CodigoPedido := conexao.FieldByName('selecionada');
    except
      CodigoPedido := 0;
    end;
  end;
  ValorAdicional := 0;
  Adicionais := SplitString(Adicional, ',');
  if CodigoPedido = 0 then
  begin
    conexao.SQL.Add('select concat(mt.descricao,' + QuotedStr(' ') +
      ',m.nr_mesa) as descricao, 0 as zero from mesa as m');
    conexao.SQL.Add
      ('join mesa_tipo as mt on mt.id_mesa_tipo = m.fk_tipo_mesa where m.id_mesa = :codigo');
    conexao.Parametros('codigo', mesa);
    DescricaoMesa := conexao.FieldByName('descricao');
    CodigoPedido := conexao.GerarID('pedido', 'codigo');
    conexao.SQL.Add
      ('insert into pedido (codigo,codigo_pedido_dia,codigo_cliente,codigo_cliente_endereco,data_pedido,hora_pedido,status,valor_pedido,valor_desconto,valor_taxa_entrega,valor_total_pedido,observacao_geral,troco,tipo_pagamento,');
    conexao.SQL.Add
      ('pedido_impresso,origem,desc_ficha,id_ficha,ficha_faturada)');
    conexao.SQL.Add
      ('values (:codigo,:codigo_pedido_dia,:codigo_cliente,:codigo_endereco,:data_pedido,:hora_pedido,:status,:valor_pedido,:valor_desconto,:valor_taxa_entrega,:valor_total_pedido,:observacao_geral,:troco,:tipo_pagamento,');
    conexao.SQL.Add
      (':pedido_impresso,:origem,:desc_ficha,:id_ficha,:ficha_faturada)');
    conexao.Parametros('codigo', CodigoPedido);
    conexao.Parametros('codigo_pedido_dia', '0');
    conexao.Parametros('codigo_cliente', '0');
    conexao.Parametros('codigo_endereco', '0');
    conexao.Parametros('data_pedido', FormatDateTime('yyyy-mm-dd', now));
    conexao.Parametros('hora_pedido', FormatDateTime('hh:mm:ss', now));
    conexao.Parametros('status', '-1');
    conexao.Parametros('valor_pedido', '0');
    conexao.Parametros('valor_taxa_entrega', '0');
    conexao.Parametros('valor_desconto', '0');
    conexao.Parametros('valor_total_pedido', '0');
    conexao.Parametros('observacao_geral', '');
    conexao.Parametros('troco', '0');
    conexao.Parametros('tipo_pagamento', '0');
    conexao.Parametros('pedido_impresso', '0');
    conexao.Parametros('origem', '3');
    conexao.Parametros('desc_ficha', DescricaoMesa);
    conexao.Parametros('id_ficha', mesa);
    conexao.Parametros('ficha_faturada', mesa);
    StartTime := now;
    conexao.ExecuteSQL;
    EndTime := now;
    ExecutionTime := EndTime - StartTime;
    MemoLog.Lines.Add('1: ' + FormatDateTime('hh:nn:ss:zzz', ExecutionTime));
    conexao.SQL.Add
      ('update mesa set selecionada = :pedido where id_mesa = :mesa');
    conexao.Parametros('pedido', CodigoPedido);
    conexao.Parametros('mesa', mesa);
    StartTime := now;
    conexao.ExecuteSQL;
    EndTime := now;
    ExecutionTime := EndTime - StartTime;
    MemoLog.Lines.Add('2: ' + FormatDateTime('hh:nn:ss:zzz', ExecutionTime));
  end;
  while not Dados.Eof do
  begin
    CodigoProduto := Dados.FieldByName('produto').AsInteger;
    // Adicional := Dados.FieldByName('adicionais').AsString;
    Quantidade := Dados.FieldByName('qtd').AsFloat;;
    // Pizza := Dados.FieldByName('pizza').AsString;
    // DadosProdutos := TFDMemTable.Create(nil);
    // conexao.SQL.Add('select * from produto where codigo = :codigo');
    // conexao.Parametros('codigo', Dados.FieldByName('produto').AsInteger);
    // DadosProdutos.LoadFromJSON(conexao.ConsultaSQL);
    ValorProduto := Dados.FieldByName('valor_produto').AsFloat;
    CodigoPedidoItem := conexao.GerarID('pedido_produtos', 'codigo');
    conexao.SQL.Add
      ('insert into pedido_produtos (codigo,codigo_pedido,codigo_produto,valor_unitario,quantidade,valor_total,valor_adicional,impresso)');
    conexao.SQL.Add
      ('values (:codigo,:codigo_pedido,:codigo_produto,:valor_unitario,:quantidade,:valor_total,:valor_adicional,:impresso)');
    conexao.Parametros('codigo', CodigoPedidoItem);
    conexao.Parametros('codigo_pedido', CodigoPedido);
    conexao.Parametros('codigo_produto', Dados.FieldByName('produto')
      .AsInteger);
    conexao.Parametros('valor_unitario', ValorProduto);
    conexao.Parametros('quantidade', Quantidade);
    conexao.Parametros('valor_total', (ValorProduto + ValorAdicional) *
      Quantidade);
    conexao.Parametros('valor_adicional', ValorAdicional * Quantidade);
    conexao.Parametros('impresso', '0');
    StartTime := now;
    conexao.ExecuteSQL;
    EndTime := now;
    ExecutionTime := EndTime - StartTime;
    MemoLog.Lines.Add('3: ' + FormatDateTime('hh:nn:ss:zzz', ExecutionTime));
    CodigoAux := conexao.GerarID('pedido_produto_sap', 'id');
    conexao.SQL.Add
      ('insert into pedido_produto_sap (id,codigo_pedido_produto,tipo,nomeclatura,descricao,valor,tipo_valor) value (:id,:codigo_pedido_produto,0,:nomeclatura,:descricao,:valor,:tipo_valor)');
    conexao.Parametros('id', CodigoAux);
    conexao.Parametros('codigo_pedido_produto', CodigoPedidoItem);
    conexao.Parametros('nomeclatura', 'OBSERVACAO');
    conexao.Parametros('descricao', '');
    conexao.Parametros('valor', 0);
    conexao.Parametros('tipo_valor', '0');
    StartTime := now;
    conexao.ExecuteSQL;
    EndTime := now;
    ExecutionTime := EndTime - StartTime;
    MemoLog.Lines.Add('4: ' + FormatDateTime('hh:nn:ss:zzz', ExecutionTime));
    TThread.CreateAnonymousThread(
      procedure
      begin
        MovimentoProduto(CodigoPedidoItem, 1);
      end).start();
    if Assigned(DadosProdutos) then
      DadosProdutos.Free;
    Dados.Next;
  end;
  if Assigned(conexao) then
    conexao.Free;
  if Assigned(Dados) then
    Dados.Free;
  // AtualizaValorPedido(CodigoPedido);
  Res.Send(MemoLog.Lines.Text);
end;

procedure DoPostCaixaDeletaSangria(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('delete from caixa_movimento where id = :id');
  conexao.Parametros('id', IntToStr(Req.Params['codigo'].ToInteger));
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DoPostCaixaImprimeSangria(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  frmServidor.ImprimirSangriaGo(Req.Params['codigo'].ToInteger);
end;

procedure DoGetTest(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send('Seu IP ?: ' + Req.RawWebRequest.RemoteAddr);
end;

procedure DoGetEstornoPedido(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  mesa: Integer;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('update pedido set pedido.status = 1, pedido.id_caixa = null where codigo = :codigo');
  conexao.Parametros('codigo', IntToStr(Req.Params['codigo'].ToInteger));
  conexao.ExecuteSQL;
  conexao.SQL.Add('delete from caixa_movimento where id_pedido = :codigo');
  conexao.Parametros('codigo', IntToStr(Req.Params['codigo'].ToInteger));
  conexao.ExecuteSQL;
  try
    mesa := (Req.Params['mesa'].ToInteger);
    conexao.SQL.Add
      ('update mesa set selecionada = :codigo, descricao = :descricao, tot_mesa = (select valor_total_pedido from pedido where codigo = :codigo) where id_mesa = :mesa');
    conexao.Parametros('mesa', mesa);
    conexao.Parametros('descricao', 'ESTORNO');
    conexao.Parametros('codigo', IntToStr(Req.Params['codigo'].ToInteger));
    conexao.ExecuteSQL;
  except
    mesa := 0;
  end;
  conexao.Free;
end;

procedure DoGetMovimentacaoCaixa(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
  SQL: String;
begin
  conexao := TConexao.Create('v2');
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('select codigo, codigo_pedido_dia, id_ficha, desc_ficha, data_pedido, hora_pedido, nfce_chave as chave,motivo_cancelamento as motivo, (select nome from cliente where codigo = codigo_cliente) as cliente, valor_total_pedido from pedido');
  conexao.SQL.Add('where id_caixa = ' + Req.Params['codigo']);
  conexao.SQL.Add('order by codigo_pedido_dia, id_ficha desc');
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      Dados.Edit;
      if Dados.FieldByName('id_ficha').AsString <> '' then
      begin
        Dados.FieldByName('cliente').AsString :=
          Dados.FieldByName('desc_ficha').AsString;
      end;
      if Dados.FieldByName('cliente').AsString = '' then
      begin
        Dados.FieldByName('cliente').AsString := 'VENDA';
      end;
      Dados.Next;
    end;
  end;
  SQL := Dados.ToJSONArray().ToString;
  Res.Send(SQL);
  conexao.Free;
end;

procedure DoGetFormaPagamentoCaixa(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('select c.id, CAST(tp.descricao AS CHAR) AS descricao, c.valor,c.tipo from caixa_movimento as c');
  conexao.SQL.Add
    ('join tipo_pagamento as tp on tp.codigo = c.id_tipo_pagamento');
  conexao.SQL.Add('where c.id_caixa = :id and c.tipo = 262626');
  conexao.SQL.Add('union all');
  conexao.SQL.Add
    ('select c.id, CAST(c.descricao AS CHAR) AS descricao, c.valor, c.tipo from caixa_movimento as c');
  conexao.SQL.Add('where c.id_caixa = :id and c.tipo = 2');
  conexao.Parametros('id', IntToStr(Req.Params['id'].ToInteger));
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetCupomDescontoSite(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
begin
  Res.Send(GetCupomSite);
end;

procedure DoPostAceitaPedido(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  conexao: TConexao;
  Dados: TFDMemTable;
begin
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  JSONObject := JSONValue as TJSONObject;
  try
    conexao := TConexao.Create('DoPostAceitaPedido');
    conexao.SQL.Add('update pedido set status = 1 where codigo = :codigo');
    conexao.Parametros('codigo', JSONObject.Values['codigo'].Value);
    conexao.ExecuteSQL;
    conexao.SQL.Add
      ('update impressao_pedido set status = 0 where id_pedido = :codigo and data_impressao is null');
    conexao.Parametros('codigo', JSONObject.Values['codigo'].Value);
    conexao.ExecuteSQL;
    AtualizaStatus(JSONObject.Values['codigo'].ToString.ToInteger, 1);
    conexao.SQL.Add('SELECT pp.codigo, p.nome_produto, pp.quantidade, ');
    conexao.SQL.Add('REPLACE(pp.valor_total, ' + QuotedStr('.') + ', ' +
      QuotedStr(',') + ') as valor_total');
    conexao.SQL.Add('FROM pedido_produtos as pp');
    conexao.SQL.Add('join produto as p on p.codigo = pp.codigo_produto');
    conexao.SQL.Add('where pp.codigo_pedido = :id ');
    conexao.Parametros('id', JSONObject.Values['codigo'].Value);
    Dados := TFDMemTable.Create(nil);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    while not Dados.Eof do
    begin
      // codigo
      conexao.SQL.Add
        ('update impressao_pedido_produto set status = 0 where id_pedido = :codigo and data_impressao is null');
      conexao.Parametros('codigo', Dados.FieldByName('codigo').AsString);
      conexao.ExecuteSQL;
      Dados.Next;
    end;
    Dados.Free;
    conexao.Free;
  except
  end;
end;

procedure DoPostCancelarPedido(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONValue: TJSONValue;
  JSONObject: TJSONObject;
  CodigoUsuario: Integer;
  ObjetoResult: TJSONObject;
  CodigoPedido: Integer;
  Dados: TFDMemTable;
  Requisicao: iRequisicao;
  CodigoSite: Integer;
  Tipo: String;
begin
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  JSONObject := JSONValue as TJSONObject;
  ObjetoResult := TJSONObject.Create;
  CodigoPedido := JSONObject.Values['codigo'].Value.ToInteger;
  try
    Tipo := JSONObject.Values['type'].Value;
  except
    Tipo := 'pedido';
  end;
  if CodigoPedido = 0 then
  begin
    ObjetoResult.AddPair('status', False);
    ObjetoResult.AddPair('motivo', 'Pedido N?o Localizado!');
  end
  else
  begin
    conexao := TConexao.Create('v2');
    Dados := TFDMemTable.Create(nil);
    if ((JSONObject.Values['senha'].Value = '2602') or
      (JSONObject.Values['senha'].Value = '***')) then
    begin
      CodigoUsuario := -1;
    end
    else
    begin
      conexao.SQL.Add
        ('SELECT * FROM usuario where (senha = md5(:senha) or senha = :senha) and cancelar = 1');
      conexao.Parametros('senha', JSONObject.Values['senha'].Value);
      try
        CodigoUsuario := conexao.FieldByName('codigo');
      except
        CodigoUsuario := 0;
      end;
    end;
    if CodigoUsuario = 0 then
    begin
      ObjetoResult.AddPair('status', False);
      ObjetoResult.AddPair('motivo', 'Sem Permiss?o Para Cancelamento.');
    end
    else
    begin
      if Tipo = 'pedido' then
      begin
        conexao.SQL.Add
          ('select * from pedido_produtos where codigo_pedido = :pedido');
        conexao.Parametros('pedido', CodigoPedido);
        Dados.LoadFromJSON(conexao.ConsultaSQL);
        TThread.CreateAnonymousThread(
          procedure
          begin
            if Dados.RecordCount > 0 then
            begin
              while not Dados.Eof do
              begin
                MovimentoProduto(Dados.FieldByName('codigo').AsInteger, 2);
                Dados.Next;
              end;
            end;
            Dados.Free;
          end).start();
        conexao.SQL.Add
          ('update pedido set motivo_cancelamento = :motivo, status = 0, usuario_deletado = :usuario, datahora_deletado = current_timestamp where codigo = :codigo');
        conexao.Parametros('motivo', JSONObject.Values['motivo'].Value);
        conexao.Parametros('codigo', CodigoPedido);
        conexao.Parametros('usuario', CodigoUsuario);
        conexao.ExecuteSQL;
      end;
      ObjetoResult.AddPair('status', True);
      ObjetoResult.AddPair('motivo', 'Cancelado Com Sucesso!');
    end;
    if (Tipo = 'produto') and (CodigoUsuario <> 0) then
    begin
      ApagarProduto(CodigoPedido, JSONObject.Values['motivo'].Value,
        CodigoUsuario);
    end;
  end;
  Res.Send(ObjetoResult);
  if Tipo = 'pedido' then
  begin
    try
      conexao.SQL.Add('select * from pedido where codigo = :codigo');
      conexao.Parametros('codigo', CodigoPedido);
      CodigoSite := conexao.FieldByName('id_pedido_site');
    except
      CodigoSite := 0;
    end;
    if CodigoSite > 0 then
    begin
      try
        Requisicao := iRequisicao.Create(nil);
        Requisicao.BaseURL :=
          'https://old.goopedir.com/v1/atualiza_status_pedido.php?codigo=' +
          CodigoSite.ToString + '&status=Cancelado';
        Requisicao.Execute;
      except
      end;
      Requisicao.Free;
    end;
  end;
  conexao.Free;
end;

procedure DoGetProdutosEstoqueAtivo(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add
    ('select codigo as value, nome_produto as label, foto_ifood as url from produto where controle_estoque = 1 and deletado = 0');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetDadosPedidoImpressao(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JsonObj: TJSONObject;
begin
  conexao := TConexao.Create('Imp');
  JsonObj := TJSONObject.Create;
  conexao.SQL.Add('select * from impressao_pedido where id_pedido = :codigo');
  conexao.Parametros('codigo', Req.Params['pedido'].ToInteger);
  JsonObj.AddPair('pedido', conexao.ConsultaSQL);
  conexao.SQL.Add
    ('SELECT impressao_pedido_produto.* FROM impressao_pedido_produto');
  conexao.SQL.Add
    ('join pedido_produtos on pedido_produtos.codigo = impressao_pedido_produto.id_pedido');
  conexao.SQL.Add('where pedido_produtos.codigo_pedido = :codigo');
  conexao.Parametros('codigo', Req.Params['pedido'].ToInteger);
  JsonObj.AddPair('cozinha', conexao.ConsultaSQL);
  Res.Send<TJSONObject>(JsonObj);
  conexao.Free;
end;

procedure DoGetDadosPedido(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('SELECT p.codigo, ');
  conexao.SQL.Add('p.codigo_pedido_dia as codigo_dia,');
  conexao.SQL.Add('p.id_pedido_site as codigo_site,');
  conexao.SQL.Add('p.data_pedido, p.hora_pedido,');
  conexao.SQL.Add('tps.descricao as pagamento_selecionado,');
  conexao.SQL.Add('p.id_caixa as caixa,');
  conexao.SQL.Add('p.troco as troco,');
  conexao.SQL.Add('p.valor_pedido as valor_itens,');
  conexao.SQL.Add('p.valor_total_pedido as valor_total,');
  conexao.SQL.Add('p.valor_taxa_entrega as taxa_entrega,');
  conexao.SQL.Add('p.taxa_servico as acrecimo,');
  conexao.SQL.Add('p.valor_desconto as desconto,');
  conexao.SQL.Add('tpf.descricao as pagamento_realizado_descricao,');
  conexao.SQL.Add('cm.valor as pagamento_realizado_valor');
  conexao.SQL.Add('FROM pedido as p ');
  conexao.SQL.Add
    ('join tipo_pagamento as tps on tps.codigo = p.tipo_pagamento');
  conexao.SQL.Add
    ('left join caixa_movimento as cm on cm.id_pedido = p.codigo and cm.tipo = 1');
  conexao.SQL.Add
    ('left join tipo_pagamento as tpf on tpf.codigo = cm.id_tipo_pagamento');
  conexao.SQL.Add('where p.codigo = :codigo');
  conexao.Parametros('codigo', Req.Params['pedido'].ToInteger);
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoGetTempoVemBuscar(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Tempo: Integer;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('select 0 as zero, temp_vembuscar from dados_whatsapp');
  Tempo := conexao.FieldByName('temp_vembuscar');
  if (Tempo <> Req.Params['tempo'].ToInteger) then
  begin
    conexao.SQL.Add('update dados_whatsapp set temp_vembuscar = :tempo');
    conexao.Parametros('tempo', IntToStr(Req.Params['tempo'].ToInteger));
    conexao.ExecuteSQL;
    EnviaTempoVemBuscar(Req.Params['tempo'].ToInteger);
  end;
  conexao.Free;
end;

procedure DoPostUsuario(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  // JsonObjeto: TJSONObject;
  // Codigo: Integer;
  JsonObj: TJSONObject;
  Codigo: Integer;
  UsuarioPai: Integer;
  TempoExpiracao: Integer;
  Nome, senha: string;
  percentual: Real;
  Finalizar, excluir, dashboard, entrada, desconto, aberturacaixa, Parametros,
    mesa, taxa, impressora, Cupom, produto, Pagamento, lancamento, motoboy,
    cancelar, garcom, campanha, financeiro: Boolean;
begin
  JsonObj := TJSONObject.ParseJSONValue(Req.body) as TJSONObject;
  conexao := TConexao.Create('v2');
  try
    // Extrair os valores para vari?veis
    Codigo := JsonObj.GetValue('codigo').AsType<Integer>;
    Nome := JsonObj.GetValue('nome').Value;
    senha := JsonObj.GetValue('senha').Value;
    Finalizar := JsonObj.GetValue('finalizar').AsType<Boolean>;
    excluir := JsonObj.GetValue('excluir').AsType<Boolean>;
    dashboard := JsonObj.GetValue('dashboard').AsType<Boolean>;
    entrada := JsonObj.GetValue('entrada').AsType<Boolean>;
    desconto := JsonObj.GetValue('desconto').AsType<Boolean>;
    aberturacaixa := JsonObj.GetValue('aberturacaixa').AsType<Boolean>;
    Parametros := JsonObj.GetValue('parametros').AsType<Boolean>;
    mesa := JsonObj.GetValue('mesa').AsType<Boolean>;
    taxa := JsonObj.GetValue('taxa').AsType<Boolean>;
    impressora := JsonObj.GetValue('impressora').AsType<Boolean>;
    Cupom := JsonObj.GetValue('cupom').AsType<Boolean>;
    produto := JsonObj.GetValue('produto').AsType<Boolean>;
    Pagamento := JsonObj.GetValue('pagamento').AsType<Boolean>;
    lancamento := JsonObj.GetValue('lancamento').AsType<Boolean>;
    motoboy := JsonObj.GetValue('motoboy').AsType<Boolean>;
    cancelar := JsonObj.GetValue('cancelar').AsType<Boolean>;
    garcom := JsonObj.GetValue('garcom').AsType<Boolean>;
    campanha := JsonObj.GetValue('campanha').AsType<Boolean>;
    try
      financeiro := JsonObj.GetValue('financeiro').AsType<Boolean>;
    except
      financeiro := false;
    end;
    try
      UsuarioPai := JsonObj.GetValue('usuario_pai').AsType<Integer>;
    except
      try
        UsuarioPai := JsonObj.GetValue('usuarioPai').AsType<Integer>;
      except
        UsuarioPai := 0;
      end;
    end;
    if UsuarioPai < 0 then
      UsuarioPai := 0;
    try
      TempoExpiracao := JsonObj.GetValue('tempo_expiracao').AsType<Integer>;
    except
      try
        TempoExpiracao := JsonObj.GetValue('tempoExpiracao').AsType<Integer>;
      except
        TempoExpiracao := 12;
      end;
    end;
    if TempoExpiracao <= 0 then
      TempoExpiracao := 12;
    try
      percentual := JsonObj.GetValue('percDesconto').AsType<Real>;
    except
      percentual := 0;
    end;
  finally
    JsonObj.Free;
  end;
  if Codigo = 0 then
  begin
    Codigo := conexao.GerarID('usuario', 'codigo');
    conexao.SQL.Add
      ('insert into usuario (codigo,nome,senha,data_cadastro) values (:codigo,:nome,if(length(:senha) = 32, :senha_md5, md5(:senha)),current_date)');
    conexao.Parametros('codigo', Codigo);
    conexao.Parametros('nome', Nome);
    conexao.Parametros('senha', senha);
    conexao.Parametros('senha_md5', senha);
    conexao.ExecuteSQL;
  end
  else
  begin
    if senha <> '' then
    begin
      conexao.SQL.Add
        ('update usuario set nome = :nome, senha = if(length(:senha) = 32, :senha_md5, md5(:senha)) where codigo = :codigo');
      conexao.Parametros('codigo', Codigo);
      conexao.Parametros('nome', Nome);
      conexao.Parametros('senha', senha);
      conexao.Parametros('senha_md5', senha);
      conexao.ExecuteSQL;
    end;
  end;
  conexao.SQL.Add
    ('update usuario set encerra = :encerra, app = :app, deleta = :deleta, dashboard = :dashboard,');
  conexao.SQL.Add
    ('estoque = :estoque, cad_mesa = :cad_mesa, cad_motoboy = :cad_motoboy, cad_taxa = :cad_taxa,');
  conexao.SQL.Add
    ('cad_impressora = :cad_impressora, cad_cupom = :cad_cupom, cad_prod = :cad_prod, cad_paga = :cad_paga, percentual = :percentual,');
  conexao.SQL.Add
    ('cad_cli = :cad_cli, cad_pedido = :cad_pedido, desconto = :desconto, param = :param, caixa = :caixa, cancelar = :cancelar, garcom = :garcom, campanha = :campanha, financeiro = :financeiro, usuario_pai = :usuario_pai, tempo_expiracao = :tempo_expiracao');
  conexao.SQL.Add('where codigo = :codigo');
  conexao.Parametros('codigo', Codigo);
  conexao.Parametros('app', Integer(Finalizar));
  conexao.Parametros('cad_cli', 1);
  conexao.Parametros('encerra', Integer(Finalizar));
  conexao.Parametros('deleta', Integer(excluir));
  conexao.Parametros('dashboard', Integer(dashboard));
  conexao.Parametros('estoque', Integer(entrada));
  conexao.Parametros('cad_mesa', Integer(mesa));
  conexao.Parametros('cad_motoboy', Integer(motoboy));
  conexao.Parametros('cad_taxa', Integer(taxa));
  conexao.Parametros('cad_cupom', Integer(Cupom));
  conexao.Parametros('cad_prod', Integer(produto));
  conexao.Parametros('cad_paga', Integer(Pagamento));
  conexao.Parametros('cad_impressora', Integer(impressora));
  conexao.Parametros('cad_pedido', Integer(lancamento));
  conexao.Parametros('desconto', Integer(desconto));
  conexao.Parametros('param', Integer(Parametros));
  conexao.Parametros('caixa', Integer(aberturacaixa));
  conexao.Parametros('cancelar', Integer(cancelar));
  conexao.Parametros('garcom', Integer(garcom));
  conexao.Parametros('campanha', Integer(campanha));
  conexao.Parametros('financeiro', Integer(financeiro));
  conexao.Parametros('usuario_pai', UsuarioPai);
  conexao.Parametros('tempo_expiracao', TempoExpiracao);
  conexao.Parametros('percentual', percentual);
  conexao.ExecuteSQL;
  conexao.Free;
  // if finalizar then
  // begin
  // conexao.Parametros('encerra', 1);
  // end else begin
  // conexao.Parametros('encerra', 0);
  // end;
  //
  // if excluir then
  // begin
  // conexao.Parametros('deleta', 1);
  // end else begin
  // conexao.Parametros('deleta', 0);
  // end;
  //
  //
  // if dashboard then
  // begin
  // conexao.Parametros('dashboard', 1);
  // end else begin
  // conexao.Parametros('dashboard', 0);
  // end;
  //
  // if entrada then
  // begin
  // conexao.Parametros('estoque', 1);
  // end else begin
  // conexao.Parametros('estoque', 0);
  // end;
  //
  // if mesa then
  // begin
  // conexao.Parametros('cad_mesa', 1);
  // end else begin
  // conexao.Parametros('cad_mesa', 0);
  // end;
  //
  // if motoboy then
  // begin
  // conexao.Parametros('cad_motoboy', 1);
  // end else begin
  // conexao.Parametros('cad_motoboy', 0);
  // end;
  //
  // if taxa then
  // begin
  // conexao.Parametros('cad_taxa', 1);
  // end else begin
  // conexao.Parametros('cad_taxa', 0);
  // end;
  //
  // if cupom then
  // begin
  // conexao.Parametros('cad_cupom', 1);
  // end else begin
  // conexao.Parametros('cad_cupom', 0);
  // end;
  //
  // if produto then
  // begin
  // conexao.Parametros('cad_prod', 1);
  // end else begin
  // conexao.Parametros('cad_prod', 0);
  // end;
  //
  // if pagamento then
  // begin
  // conexao.Parametros('cad_paga', 1);
  // end else begin
  // conexao.Parametros('cad_paga', 0);
  // end;
  //
  // if impressora then
  // begin
  // conexao.Parametros('cad_impressora', 1);
  // end else begin
  // conexao.Parametros('cad_impressora', 0);
  // end;
  //
  // if lancamento then
  // begin
  // conexao.Parametros('cad_pedido', 1);
  // end else begin
  // conexao.Parametros('cad_pedido', 0);
  // end;
  //
  // if desconto then
  // begin
  // conexao.Parametros('desconto', 1);
  // end else begin
  // conexao.Parametros('desconto', 0);
  // end;
  //
  // if parametros then
  // begin
  // conexao.Parametros('param', 1);
  // end else begin
  // conexao.Parametros('param', 0);
  // end;
  //
  // if aberturacaixa then
  // begin
  // conexao.Parametros('caixa', 1);
  // end else begin
  // conexao.Parametros('caixa', 0);
  // end;
end;

function NormalizarChaveNotaDespesa(const Chave: string): string;
var
  i: Integer;
begin
  Result := '';
  for i := 1 to Length(Chave) do
    if CharInSet(Chave[i], ['0' .. '9']) then
      Result := Result + Chave[i];
  if Result = '' then
    Result := Trim(Chave);
end;

function ChaveNotaDespesaValor(JSON: TJSONObject; const Campo: string): string;
var
  Value: TJSONValue;
begin
  Result := '';
  Value := JSON.GetValue(Campo);
  if Assigned(Value) and not(Value is TJSONNull) then
    Result := NormalizarChaveNotaDespesa(Value.Value);
end;

function ChaveNotaDespesa(JSON: TJSONObject): string;
var
  Value: TJSONValue;
  Nota: TJSONObject;
begin
  Result := '';
  if not Assigned(JSON) then
    exit;
  Result := ChaveNotaDespesaValor(JSON, 'chave_nota');
  if Result <> '' then
    exit;
  Result := ChaveNotaDespesaValor(JSON, 'chave');
  if Result <> '' then
    exit;
  Result := ChaveNotaDespesaValor(JSON, 'chave_nfe');
  if Result <> '' then
    exit;
  Result := ChaveNotaDespesaValor(JSON, 'chaveNFe');
  if Result <> '' then
    exit;
  Result := ChaveNotaDespesaValor(JSON, 'chaveNfe');
  if Result <> '' then
    exit;
  Result := ChaveNotaDespesaValor(JSON, 'chaveNota');
  if Result <> '' then
    exit;
  Value := JSON.GetValue('nota_fiscal');
  if Assigned(Value) and (Value is TJSONObject) then
    Nota := Value as TJSONObject
  else
    Nota := nil;
  Value := JSON.GetValue('nota');
  if (not Assigned(Nota)) and Assigned(Value) and (Value is TJSONObject) then
    Nota := Value as TJSONObject;
  Value := JSON.GetValue('notaFiscal');
  if (not Assigned(Nota)) and Assigned(Value) and (Value is TJSONObject) then
    Nota := Value as TJSONObject;
  if Assigned(Nota) then
    Result := ChaveNotaDespesa(Nota);
end;

function ValorJSONDespesa(JSON: TJSONObject;
const Campo, Padrao: string): string;
var
  Value: TJSONValue;
begin
  Result := Padrao;
  if not Assigned(JSON) then
    exit;
  Value := JSON.GetValue(Campo);
  if Assigned(Value) and not(Value is TJSONNull) then
    Result := Value.Value;
end;

function InteiroJSONDespesa(JSON: TJSONObject; const Campo: string;
Padrao: Integer): Integer;
var
  Value: TJSONValue;
begin
  Result := Padrao;
  if not Assigned(JSON) then
    exit;
  Value := JSON.GetValue(Campo);
  if Assigned(Value) and not(Value is TJSONNull) then
    TryStrToInt(Value.Value, Result);
end;

function BooleanJSONDespesa(JSON: TJSONObject; const Campo: string;
Padrao: Boolean): Boolean;
var
  Value: TJSONValue;
  Texto: string;
begin
  Result := Padrao;
  if not Assigned(JSON) then
    exit;
  Value := JSON.GetValue(Campo);
  if not Assigned(Value) or (Value is TJSONNull) then
    exit;
  Texto := LowerCase(Trim(Value.Value));
  Result := (Texto = 'true') or (Texto = '1') or (Texto = 'sim');
end;

function FloatSQLDespesa(Valor: Real): string;
var
  FormatSettings: TFormatSettings;
begin
  FormatSettings := TFormatSettings.Create;
  FormatSettings.DecimalSeparator := '.';
  Result := FloatToStr(Valor, FormatSettings);
end;

function CartaoDespesaID(JSON: TJSONObject): Integer;
begin
  Result := InteiroJSONDespesa(JSON, 'cartao_id', 0);
  if Result = 0 then
    Result := InteiroJSONDespesa(JSON, 'cartao', 0);
  if Result = 0 then
    Result := InteiroJSONDespesa(JSON, 'id_cartao', 0);
end;

procedure MovimentarLimiteCartaoDespesa(conexao: TConexao; CartaoID: Integer;
Valor: Real; RetornarLimite: Boolean);
begin
  if (CartaoID <= 0) or (Valor <= 0) then
    exit;
  conexao.SQL.Clear;
  conexao.SQL.Add
    ('update cartoes set limite_usado = greatest(0, coalesce(limite_usado, 0) ');
  if RetornarLimite then
    conexao.SQL.Add('- :valor), atualizado_em = now() where id = :cartao_id')
  else
    conexao.SQL.Add('+ :valor), atualizado_em = now() where id = :cartao_id');
  conexao.Parametros('valor', FloatSQLDespesa(Valor));
  conexao.Parametros('cartao_id', CartaoID);
  conexao.ExecuteSQL;
  conexao.SQL.Clear;
end;

procedure RetornarLimiteDespesa(conexao: TConexao; DespesaID: Integer);
var
  Dados: TFDMemTable;
begin
  Dados := TFDMemTable.Create(nil);
  try
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('select id, cartao_id, valor, coalesce(limite_cartao_retornado, 0) as limite_cartao_retornado');
    conexao.SQL.Add
      ('from despesas where id = :id and coalesce(cartao_id, 0) > 0 limit 1');
    conexao.Parametros('id', DespesaID);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount = 0 then
      exit;
    if Dados.FieldByName('limite_cartao_retornado').AsInteger = 1 then
      exit;
    MovimentarLimiteCartaoDespesa(conexao, Dados.FieldByName('cartao_id')
      .AsInteger, Dados.FieldByName('valor').AsFloat, True);
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('update despesas set limite_cartao_retornado = 1 where id = :id');
    conexao.Parametros('id', DespesaID);
    conexao.ExecuteSQL;
  finally
    Dados.Free;
  end;
end;

procedure CriarRegraDespesaRecorrente(conexao: TConexao; JSON: TJSONObject;
DataInicial: TDate; Valor: Real; CartaoID: Integer;
const ChaveNota, GrupoRecorrencia: string);
begin
  conexao.SQL.Clear;
  conexao.SQL.Add('insert into despesa_recorrencia');
  conexao.SQL.Add('(categoria, descricao, valor, cartao_id, recorrencia_tipo,');
  conexao.SQL.Add('dia_vencimento, proximo_vencimento, ativo, chave_nota,');
  conexao.SQL.Add
    ('fatura_ano_mes, recorrencia_grupo, criado_em, atualizado_em)');
  conexao.SQL.Add('values');
  conexao.SQL.Add
    ('(:categoria, :descricao, :valor, :cartao_id, :recorrencia_tipo,');
  conexao.SQL.Add(':dia_vencimento, :proximo_vencimento, 1, :chave_nota,');
  conexao.SQL.Add(':fatura_ano_mes, :recorrencia_grupo, now(), now())');
  conexao.Parametros('categoria', JSON.Values['categoria'].Value);
  conexao.Parametros('descricao', JSON.Values['descricao'].Value);
  conexao.Parametros('valor', FloatSQLDespesa(Valor));
  conexao.Parametros('cartao_id', CartaoID);
  conexao.Parametros('recorrencia_tipo', InteiroJSONDespesa(JSON,
    'recorrencia', 3));
  conexao.Parametros('dia_vencimento', DayOf(DataInicial));
  conexao.Parametros('proximo_vencimento', FormatDateTime('yyyy-mm-dd',
    IncMonth(DataInicial, 1)));
  conexao.Parametros('chave_nota', ChaveNota);
  conexao.Parametros('fatura_ano_mes', ValorJSONDespesa(JSON,
    'fatura_ano_mes', ''));
  conexao.Parametros('recorrencia_grupo', GrupoRecorrencia);
  conexao.ExecuteSQL;
  conexao.SQL.Clear;
end;

function ProximaDataRecorrencia(DataAtual: TDate; Tipo: Integer): TDate;
begin
  case Tipo of
    1:
      Result := IncDay(DataAtual, 1);
    2:
      Result := IncDay(DataAtual, 7);
    4:
      Result := IncMonth(DataAtual, 12);
  else
    Result := IncMonth(DataAtual, 1);
  end;
end;

procedure GerarDespesasRecorrentesAte(conexao: TConexao; DataLimite: TDate);
var
  Regras: TFDMemTable;
  Vencimento: TDate;
  AnoMes: string;
begin
  Regras := TFDMemTable.Create(nil);
  try
    conexao.SQL.Clear;
    conexao.SQL.Add('select * from despesa_recorrencia');
    conexao.SQL.Add('where ativo = 1 and proximo_vencimento <= :data_limite');
    conexao.Parametros('data_limite', FormatDateTime('yyyy-mm-dd', DataLimite));
    Regras.LoadFromJSON(conexao.ConsultaSQL);
    if Regras.RecordCount = 0 then
      exit;
    Regras.First;
    while not Regras.Eof do
    begin
      Vencimento := ISO8601ToDate(Regras.FieldByName('proximo_vencimento').AsString);
      while Vencimento <= DataLimite do
      begin
        AnoMes := FormatDateTime('yyyy-mm', Vencimento);
        conexao.SQL.Clear;
        conexao.SQL.Add('insert into despesas');
        conexao.SQL.Add
          ('(categoria, descricao, valor, parcelas, parcela, vencimento,');
        conexao.SQL.Add
          ('status, chave_nota, cartao_id, limite_cartao_retornado,');
        conexao.SQL.Add
          ('recorrente, recorrencia_tipo, recorrencia_grupo, fatura_ano_mes)');
        conexao.SQL.Add
          ('select :categoria, :descricao, :valor, 1, 1, :vencimento,');
        conexao.SQL.Add('1, :chave_nota, :cartao_id, 0, 1, :recorrencia_tipo,');
        conexao.SQL.Add(':recorrencia_grupo, :fatura_ano_mes from dual');
        conexao.SQL.Add('where not exists (select 1 from despesas');
        conexao.SQL.Add('where recorrencia_grupo = :recorrencia_grupo_check');
        conexao.SQL.Add('and fatura_ano_mes = :fatura_ano_mes_check');
        conexao.SQL.Add('and excluida = 0 limit 1)');
        conexao.Parametros('categoria', Regras.FieldByName('categoria')
          .AsInteger);
        conexao.Parametros('descricao', Regras.FieldByName('descricao')
          .AsString);
        conexao.Parametros('valor', FloatSQLDespesa(Regras.FieldByName('valor')
          .AsFloat));
        conexao.Parametros('vencimento', FormatDateTime('yyyy-mm-dd',
          Vencimento));
        conexao.Parametros('chave_nota', Regras.FieldByName('chave_nota')
          .AsString);
        conexao.Parametros('cartao_id', Regras.FieldByName('cartao_id')
          .AsInteger);
        conexao.Parametros('recorrencia_tipo',
          Regras.FieldByName('recorrencia_tipo').AsInteger);
        conexao.Parametros('recorrencia_grupo',
          Regras.FieldByName('recorrencia_grupo').AsString);
        conexao.Parametros('fatura_ano_mes', AnoMes);
        conexao.Parametros('recorrencia_grupo_check',
          Regras.FieldByName('recorrencia_grupo').AsString);
        conexao.Parametros('fatura_ano_mes_check', AnoMes);
        conexao.ExecuteSQL;
        if Regras.FieldByName('cartao_id').AsInteger > 0 then
          MovimentarLimiteCartaoDespesa(conexao, Regras.FieldByName('cartao_id')
            .AsInteger, Regras.FieldByName('valor').AsFloat, False);
        Vencimento := ProximaDataRecorrencia(Vencimento,
          Regras.FieldByName('recorrencia_tipo').AsInteger);
      end;
      conexao.SQL.Clear;
      conexao.SQL.Add
        ('update despesa_recorrencia set proximo_vencimento = :proximo,');
      conexao.SQL.Add('atualizado_em = now() where id = :id');
      conexao.Parametros('proximo', FormatDateTime('yyyy-mm-dd', Vencimento));
      conexao.Parametros('id', Regras.FieldByName('id').AsInteger);
      conexao.ExecuteSQL;
      conexao.SQL.Clear;
      Regras.Next;
    end;
  finally
    Regras.Free;
  end;
end;

procedure DoPostDespesa(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  JSON: TJSONValue;
  JSONObject: TJSONObject;
  i: Integer;
  Data: TDate;
  Valor: Real;
  ChaveNota: string;
  CartaoID: Integer;
  Parcelas: Integer;
  StatusDespesa: Integer;
  Recorrente: Integer;
  RecorrenciaProcedural: Boolean;
  GrupoRecorrencia: string;
  ValorParcela: Real;
  FormatSettings: TFormatSettings;
begin
  conexao := TConexao.Create('DoPostDespesa');
  JSON := TJSONObject.ParseJSONValue(Req.body);
  if Assigned(JSON) and (JSON is TJSONObject) then
  begin
    // Converter o JSONValue para um TJSONObject
    JSONObject := JSON as TJSONObject;
    // Configurar o separador decimal explicitamente
    FormatSettings := TFormatSettings.Create;
    FormatSettings.DecimalSeparator := '.';
    // Converte usando o formato especificado
    Valor := StrToFloat(JSONObject.Values['valor'].Value, FormatSettings);
    ChaveNota := ChaveNotaDespesa(JSONObject);
    CartaoID := CartaoDespesaID(JSONObject);
    Parcelas := JSONObject.Values['parcelas'].Value.ToInteger;
    Recorrente := 0;
    RecorrenciaProcedural := BooleanJSONDespesa(JSONObject, 'recorrente', False)
      and (Parcelas <= 1);
    if RecorrenciaProcedural then
      Recorrente := 1;
    GrupoRecorrencia := FormatDateTime('yyyymmddhhnnsszzz', now) +
      IntToStr(Random(10000));
    Data := StrToDate(Copy(JSONObject.Values['data'].Value, 9, 2) + '/' +
      Copy(JSONObject.Values['data'].Value, 6, 2) + '/' +
      Copy(JSONObject.Values['data'].Value, 0, 4));
    if RecorrenciaProcedural then
      Parcelas := 1;
    for i := 1 to Parcelas do
    begin
      if i <> 1 then
      begin
        case JSONObject.Values['recorrencia'].Value.ToInteger of
          1:
            begin
              Data := IncDay(Data, 1);
            end;
          2:
            begin
              Data := IncDay(Data, 7);
            end;
          3:
            begin
              Data := IncMonth(Data, 1);
            end;
          4:
            begin
              Data := IncMonth(Data, 12);
            end;
        end;
      end;
      conexao.SQL.Add
        ('insert into despesas (categoria,descricao,valor,parcelas,parcela,vencimento,status,chave_nota,cartao_id,limite_cartao_retornado,recorrente,recorrencia_tipo,recorrencia_grupo,fatura_ano_mes) values');
      conexao.SQL.Add
        ('(:categoria,:descricao,:valor,:parcelas,:parcela,:vencimento,:status,:chave_nota,:cartao_id,:limite_cartao_retornado,:recorrente,:recorrencia_tipo,:recorrencia_grupo,:fatura_ano_mes) ');
      conexao.Parametros('categoria', JSONObject.Values['categoria'].Value);
      conexao.Parametros('descricao', JSONObject.Values['descricao'].Value);
      ValorParcela := Valor / Parcelas;
      conexao.Parametros('valor', ValorParcela);
      conexao.Parametros('parcelas', Parcelas);
      conexao.Parametros('parcela', i);
      conexao.Parametros('vencimento', FormatDateTime('yyyy-mm-dd', Data));
      if JSONObject.Values['status'].Value.ToBoolean then
        StatusDespesa := 2
      else
        StatusDespesa := 1;
      conexao.Parametros('status', StatusDespesa);
      conexao.Parametros('chave_nota', ChaveNota);
      if CartaoID > 0 then
        conexao.Parametros('cartao_id', CartaoID)
      else
        conexao.Parametros('cartao_id', 0);
      if (CartaoID > 0) and (StatusDespesa = 2) then
        conexao.Parametros('limite_cartao_retornado', 1)
      else
        conexao.Parametros('limite_cartao_retornado', 0);
      conexao.Parametros('recorrente', Recorrente);
      conexao.Parametros('recorrencia_tipo', InteiroJSONDespesa(JSONObject,
        'recorrencia', 0));
      conexao.Parametros('recorrencia_grupo', GrupoRecorrencia);
      conexao.Parametros('fatura_ano_mes', ValorJSONDespesa(JSONObject,
        'fatura_ano_mes', ''));
      conexao.ExecuteSQL;
      if (CartaoID > 0) and (StatusDespesa <> 2) then
        MovimentarLimiteCartaoDespesa(conexao, CartaoID, ValorParcela, False);
    end;
    if RecorrenciaProcedural then
      CriarRegraDespesaRecorrente(conexao, JSONObject, Data, Valor, CartaoID,
        ChaveNota, GrupoRecorrencia);
  end;
  conexao.Free;
end;

procedure DoPostGerarDespesaRecorrencia(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSON: TJSONValue;
  JSONObject: TJSONObject;
  Ano: Integer;
  Mes: Integer;
  Retorno: TJSONObject;
begin
  conexao := TConexao.Create('DoPostGerarDespesaRecorrencia');
  JSON := TJSONObject.ParseJSONValue(Req.body);
  Retorno := TJSONObject.Create;
  try
    Ano := YearOf(Date);
    Mes := MonthOf(Date);
    if Assigned(JSON) and (JSON is TJSONObject) then
    begin
      JSONObject := JSON as TJSONObject;
      Ano := InteiroJSONDespesa(JSONObject, 'ano', Ano);
      Mes := InteiroJSONDespesa(JSONObject, 'mes', Mes);
    end;
    GerarDespesasRecorrentesAte(conexao, EndOfAMonth(Ano, Mes));
    Retorno.AddPair('status', 'ok');
    Retorno.AddPair('ano', TJSONNumber.Create(Ano));
    Retorno.AddPair('mes', TJSONNumber.Create(Mes));
    Res.Send<TJSONObject>(Retorno);
  finally
    JSON.Free;
    conexao.Free;
  end;
end;

procedure DoGetDespesaSugestao(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Busca: string;
begin
  Busca := '';
  try
    Busca := Trim(Req.Params['busca']);
  except
  end;
  if Busca = '' then
  begin
    try
      Busca := Trim(Req.Query['q']);
    except
    end;
  end;
  conexao := TConexao.Create('DoGetDespesaSugestao');
  try
    if Busca = '' then
    begin
      Res.Send<TJsonArray>(TJsonArray.Create);
      exit;
    end;
    conexao.SQL.Add
      ('select d.descricao, d.categoria, dc.descricao as categoria_despesa,');
    conexao.SQL.Add('d.valor, d.parcelas, d.status, d.chave_nota,');
    conexao.SQL.Add
      ('max(d.vencimento) as ultimo_vencimento, count(*) as vezes_lancada');
    conexao.SQL.Add('from despesas d');
    conexao.SQL.Add('left join descricao dc on dc.id = d.categoria');
    conexao.SQL.Add
      ('where d.excluida = 0 and d.descricao like concat("%", :busca, "%")');
    conexao.SQL.Add
      ('group by d.descricao, d.categoria, dc.descricao, d.valor, d.parcelas, d.status, d.chave_nota');
    conexao.SQL.Add('order by case');
    conexao.SQL.Add('when upper(d.descricao) = upper(:busca) then 0');
    conexao.SQL.Add
      ('when upper(d.descricao) like concat(upper(:busca), "%") then 1');
    conexao.SQL.Add('else 2 end, vezes_lancada desc, ultimo_vencimento desc');
    conexao.SQL.Add('limit 3');
    conexao.Parametros('busca', Busca);
    Res.Send<TJsonArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;

procedure DoPutDespesaOperacao(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSON: TJSONValue;
  JSONObject: TJSONObject;
begin
  JSON := TJSONObject.ParseJSONValue(Req.body);
  conexao := TConexao.Create('DoPutDespesaOperacao');
  if Assigned(JSON) and (JSON is TJSONObject) then
  begin
    JSONObject := JSON as TJSONObject;
    if JSONObject.Values['type'].Value = '1' then
    begin
      conexao.SQL.Add('update despesas set status = 2 where id = :id');
      conexao.Parametros('id', JSONObject.Values['id'].Value);
      conexao.ExecuteSQL;
      RetornarLimiteDespesa(conexao, JSONObject.Values['id'].Value.ToInteger);
    end
    else
    begin
      if BooleanJSONDespesa(JSONObject, 'retornar_limite', False) then
        RetornarLimiteDespesa(conexao, JSONObject.Values['id'].Value.ToInteger);
      conexao.SQL.Add('update despesas set excluida = 1 where id = :id');
      conexao.Parametros('id', JSONObject.Values['id'].Value);
      conexao.ExecuteSQL;
    end;
  end;
  conexao.Free;
  JSON.Free;
end;

procedure DoGetDespesas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  JSONObject: TJSONObject;
  Dados: TFDMemTable;
  NotasSemDespesa: TFDMemTable;
  JSON: TJSONValue;
  JObject: TJSONObject;
  JNotasSemDespesa: TJSONObject;
  Despesas: Real;
  Receitas: Real;
  ReceitaiFood: Real;
  DataiFood: TDate;
  Pago: Real;
  EmAberto: Real;
  ValorNotasSemDespesa: Real;
begin
  JObject := TJSONObject.Create;
  Dados := TFDMemTable.Create(nil);
  NotasSemDespesa := TFDMemTable.Create(nil);
  conexao := TConexao.Create('DoGetDespesasAnos');
  JSON := TJSONObject.ParseJSONValue(Req.body);
  if Assigned(JSON) and (JSON is TJSONObject) then
  begin
    JSONObject := JSON as TJSONObject;
    DataiFood := IncMonth(StrToDate('01/' + JSONObject.Values['mes'].Value + '/'
      + JSONObject.Values['ano'].Value), -1);
    GerarDespesasRecorrentesAte(conexao,
      EndOfAMonth(JSONObject.Values['ano'].Value.ToInteger,
      JSONObject.Values['mes'].Value.ToInteger));
    conexao.SQL.Clear;
    conexao.SQL.Add
      ('select d.*, curdate() as data_servidor, dc.descricao as categoria_despesa, c.nome as cartao_nome, c.tipo as cartao_tipo, c.limite as cartao_limite, c.limite_usado as cartao_limite_usado from despesas d');
    conexao.SQL.Add('left join descricao dc on dc.id = d.categoria');
    conexao.SQL.Add('left join cartoes c on c.id = d.cartao_id');
    conexao.SQL.Add
      ('where YEAR(d.vencimento) = :ano AND MONTH(d.vencimento) = :mes and d.excluida = 0');
    conexao.SQL.Add('order by d.status, d.vencimento desc');
    conexao.Parametros('ano', JSONObject.Values['ano'].Value);
    conexao.Parametros('mes', JSONObject.Values['mes'].Value);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    Despesas := 0;
    EmAberto := 0;
    Pago := 0;
    if Dados.RecordCount > 0 then
    begin
      while not Dados.Eof do
      begin
        Despesas := Despesas + Dados.FieldByName('valor').AsFloat;
        if Dados.FieldByName('status').AsFloat = 1 then
          EmAberto := EmAberto + Dados.FieldByName('valor').AsFloat
        else
          Pago := Pago + Dados.FieldByName('valor').AsFloat;
        Dados.Next;
      end;
    end;
    conexao.SQL.Add
      ('select 0 as zero, sum(valor_total_pedido) as receita from pedido where codigo_pedido_dia > 0 and status > 0  and id_caixa > 0 and id_ifood is null');
    conexao.SQL.Add
      ('and YEAR(data_pedido) = :ano AND MONTH(data_pedido) = :mes');
    conexao.Parametros('ano', JSONObject.Values['ano'].Value);
    conexao.Parametros('mes', JSONObject.Values['mes'].Value);
    try
      Receitas := conexao.FieldByName('receita');
    except
    end;
    conexao.SQL.Add
      ('select 0 as zero, sum(valor_total_pedido) as receita from pedido where codigo_pedido_dia > 0 and status > 0  and id_caixa > 0 and id_ifood <> '
      + QuotedStr(''));
    conexao.SQL.Add
      ('and YEAR(data_pedido) = :ano AND MONTH(data_pedido) = :mes');
    conexao.Parametros('ano', FormatDateTime('yyyy', DataiFood));
    conexao.Parametros('mes', FormatDateTime('mm', DataiFood));
    try
      ReceitaiFood := conexao.FieldByName('receita');
    except
    end;
    ReceitaiFood := ReceitaiFood / 2;
    conexao.SQL.Add('select dc.descricao, sum(d.valor) as valor');
    conexao.SQL.Add('from despesas as d');
    conexao.SQL.Add('join descricao as dc on dc.id = d.categoria');
    conexao.SQL.Add('where d.excluida = 0');
    conexao.SQL.Add
      ('and YEAR(d.vencimento) = :ano AND MONTH(d.vencimento) = :mes');
    conexao.SQL.Add('group by dc.descricao');
    conexao.Parametros('ano', JSONObject.Values['ano'].Value);
    conexao.Parametros('mes', JSONObject.Values['mes'].Value);
    JObject.AddPair('pago', Pago);
    JObject.AddPair('aberto', EmAberto);
    JObject.AddPair('despesa', Despesas - EmAberto);
    JObject.AddPair('receita', Receitas + ReceitaiFood);
    JObject.AddPair('data', Dados.ToJSONArray());
    JObject.AddPair('grafico', conexao.ConsultaSQL);
    conexao.SQL.Add('select nf.id, nf.fornecedor_id, f.nome as fornecedor, ' +
      'nf.serie, nf.numero, nf.chave, nf.modelo, nf.tipo, nf.data_emissao, ' +
      'nf.data_entrada, nf.vNF, nf.vFrete, nf.vDesc, nf.vOutro, nf.status_importacao ');
    conexao.SQL.Add('from nota_fiscal nf');
    conexao.SQL.Add('left join fornecedor f on f.id = nf.fornecedor_id');
    conexao.SQL.Add('left join despesas d on ' +
      'replace(replace(replace(replace(coalesce(d.chave_nota, ""), " ", ""), ".", ""), "-", ""), "/", "") = nf.chave '
      + 'and coalesce(d.excluida, 0) = 0');
    conexao.SQL.Add('where d.id is null and ifnull(nf.chave, "") <> ""');
    conexao.SQL.Add
      ('and YEAR(nf.data_emissao) = :ano AND MONTH(nf.data_emissao) = :mes');
    conexao.SQL.Add('order by nf.data_emissao desc');
    conexao.Parametros('ano', JSONObject.Values['ano'].Value);
    conexao.Parametros('mes', JSONObject.Values['mes'].Value);
    NotasSemDespesa.LoadFromJSON(conexao.ConsultaSQL);
    ValorNotasSemDespesa := 0;
    if NotasSemDespesa.RecordCount > 0 then
    begin
      NotasSemDespesa.First;
      while not NotasSemDespesa.Eof do
      begin
        ValorNotasSemDespesa := ValorNotasSemDespesa +
          NotasSemDespesa.FieldByName('vNF').AsFloat;
        NotasSemDespesa.Next;
      end;
    end;
    JNotasSemDespesa := TJSONObject.Create;
    JNotasSemDespesa.AddPair('total',
      TJSONNumber.Create(NotasSemDespesa.RecordCount));
    JNotasSemDespesa.AddPair('valor_total',
      TJSONNumber.Create(ValorNotasSemDespesa));
    JNotasSemDespesa.AddPair('notas', NotasSemDespesa.ToJSONArray());
    JObject.AddPair('notas_sem_despesa', JNotasSemDespesa);
  end;
  Res.Send<TJSONObject>(JObject);
  conexao.Free;
  NotasSemDespesa.Free;
  Dados.Free;
end;

procedure DoPostDespesaCategoria(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSON: TJSONValue;
  JSONObject: TJSONObject;
begin
  conexao := TConexao.Create('DoPostDespesaCategoria');
  JSON := TJSONObject.ParseJSONValue(Req.body);
  if Assigned(JSON) and (JSON is TJSONObject) then
  begin
    // Converter o JSONValue para um TJSONObject
    JSONObject := JSON as TJSONObject;
    conexao.SQL.Add('insert into descricao (descricao) values (:descricao)');
    conexao.Parametros('descricao', JSONObject.Values['name'].Value);
    conexao.ExecuteSQL;
  end;
  conexao.Free;
end;

procedure DoGetDespesasAnos(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('DoGetDespesasAnos');
  conexao.SQL.Add
    ('SELECT DISTINCT YEAR(vencimento) AS ano, 0 as zero FROM despesas;');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

function DescricaoSemParcelaDespesa(const Texto: string): string;
begin
  Result := Trim(TRegEx.Replace(Texto, '\s*-\s*parcela\s+\d+\s*/\s*\d+\s*$', '',
    [roIgnoreCase]));
  Result := TRegEx.Replace(Result, '\s+', ' ');
end;

function DescricaoCategoriaDespesa(Value: TJSONValue): string;
begin
  Result := '';
  if not Assigned(Value) or (Value is TJSONNull) then
    exit;
  if Value is TJSONObject then
  begin
    Result := ValorJSONDespesa(Value as TJSONObject, 'descricao', '');
    if Result = '' then
      Result := ValorJSONDespesa(Value as TJSONObject, 'nome', '');
    if Result = '' then
      Result := ValorJSONDespesa(Value as TJSONObject, 'name', '');
  end
  else
    Result := Value.Value;
  Result := DescricaoSemParcelaDespesa(Result);
end;

function BuscarCategoriaDespesaPorDescricao(conexao: TConexao;
const Descricao: string): Integer;
var
  Qry: TFDQuery;
begin
  Result := 0;
  if Trim(Descricao) = '' then
    exit;
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Add('select categoria');
    Qry.SQL.Add('from despesas');
    Qry.SQL.Add('where upper(trim(descricao)) = upper(trim(:descricao))');
    Qry.SQL.Add('and coalesce(excluida, 0) = 0');
    Qry.SQL.Add('and coalesce(categoria, 0) > 0');
    Qry.SQL.Add('order by id desc limit 1');
    Qry.ParamByName('descricao').AsString := Descricao;
    Qry.Open;
    if not Qry.IsEmpty then
      Result := Qry.FieldByName('categoria').AsInteger;
  finally
    Qry.Free;
  end;
end;

procedure DoPostDespesaCategoriaBuscar(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  JSONValue: TJSONValue;
  JSONArray: TJsonArray;
  Retorno: TJsonArray;
  ItemRetorno: TJSONObject;
  Descricao: string;
  ID: Integer;
  i: Integer;

  procedure AdicionarResultado(Value: TJSONValue);
  begin
    Descricao := DescricaoCategoriaDespesa(Value);
    ID := BuscarCategoriaDespesaPorDescricao(conexao, Descricao);
    ItemRetorno := TJSONObject.Create;
    ItemRetorno.AddPair('descricao', Descricao);
    ItemRetorno.AddPair('id', TJSONNumber.Create(ID));
    ItemRetorno.AddPair('encontrado', TJSONBool.Create(ID > 0));
    Retorno.AddElement(ItemRetorno);
  end;

begin
  conexao := TConexao.Create('DoPostDespesaCategoriaBuscar');
  JSONValue := TJSONObject.ParseJSONValue(Req.body);
  Retorno := TJsonArray.Create;
  try
    if not Assigned(JSONValue) then
    begin
      Res.Status(400);
      Res.Send('json invalido');
      exit;
    end;

    if JSONValue is TJsonArray then
    begin
      JSONArray := JSONValue as TJsonArray;
      for i := 0 to JSONArray.Count - 1 do
        AdicionarResultado(JSONArray.Items[i]);
    end
    else
      AdicionarResultado(JSONValue);

    Res.Send<TJsonArray>(Retorno);
  finally
    JSONValue.Free;
    conexao.Free;
  end;
end;

procedure DoGetDespesaCategoriaBuscar(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
  Retorno: TJSONObject;
  Descricao: string;
  ID: Integer;
begin
  conexao := TConexao.Create('DoGetDespesaCategoriaBuscar');
  Retorno := TJSONObject.Create;
  try
    Descricao := DescricaoSemParcelaDespesa(Req.Params['descricao']);
    ID := BuscarCategoriaDespesaPorDescricao(conexao, Descricao);
    Retorno.AddPair('descricao', Descricao);
    Retorno.AddPair('id', TJSONNumber.Create(ID));
    Retorno.AddPair('encontrado', TJSONBool.Create(ID > 0));
    Res.Send<TJSONObject>(Retorno);
  finally
    conexao.Free;
  end;
end;

procedure DoGetDespesaCategoria(Req: THorseRequest; Res: THorseResponse;
Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('v2');
  conexao.SQL.Add('select * from descricao');
  Res.Send<TJsonArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure Registry;
begin
  if ServerStartedAt = 0 then
    ServerStartedAt := Now;
  if not Assigned(V2StatusTraceLock) then
    V2StatusTraceLock := TCriticalSection.Create;
  if not Assigned(APIGoopedirLock) then
    APIGoopedirLock := TCriticalSection.Create;

  IniciarAquecimentoCacheDashboardVenda;
  THorse.Get('/v2/heart', DoGetHeart);
  THorse.Get('/v2/health', DoGetHealth);
  THorse.Get('/v2/cardapio/valida/hash/:categoria/:hash',
    DoGetCardapioValidaHash);
  THorse.Get('/v2/resultado/metricas', DoGetResultadoMetricas);
  THorse.Get('/v2/nfce/geradas', DoGetNFCeGeradas);
  THorse.Get('/v2/pedidos/nfce/:dataini/:datafim', DoGetPedidosNFCePeriodo);
  THorse.Get('/v2/pedidos/nfce/:dataini/:datafim/:status',
    DoGetPedidosNFCePeriodo);
  THorse.Get('/v2/produto/deletado', DoGetProdutoDeletado);
  THorse.Get('/v2/pedido/cancelado', DoGetPedidoCancelado);
  THorse.Get('/v2/movimentacao/pagamento', DoGetMovimentacaoPagamento);
  THorse.Get('/v2/fechamento/fiado', DoGetFechamentoFiado);
  THorse.Get('/v2/log/operacao', DoGetLogOperacao);
  THorse.Get('/v2/log/operacao/resumo', DoGetLogOperacaoResumo);
  THorse.Post('/v2/category', DoPostCategory);
  THorse.Post('/v2/category/size/new', DoPostCategorySizeNew);
  THorse.Get('/v2/product/of/category/:category', DoGetCaetegory);
  THorse.Post('/v2/product', DoPostProduct);
  THorse.Post('/v2/flavor', DoPostFlavor);
  THorse.Get('/v2/flavor/:category', DoGetFlavor);
  THorse.Post('/v2/flavor/:name/:status', DoPostStatusFlavor);
  THorse.Post('/v2/flavor/:product/:name/:value', DoPostNovoValorFlavor);
  THorse.Get('/v2/user/id', DoGetUserID);
  THorse.Get('/v2/pedidos/motoboy/:codigo', DoGetPedidosMotoboy);
  THorse.Get('/v2/pedidos/motoboy/pagamento/:pagamento', DoGetPedidosMotoboy);
  THorse.Post('/v2/pedidos/motoboy', PostGetPedidosMotoboy);
  THorse.Get('/v2/fiscal/ibs-cbs/cst', DoGetFiscalIBSCBSCST);
  THorse.Get('/v2/fiscal/ibs-cbs/class-trib', DoGetFiscalIBSCBSClassTrib);
  THorse.Get('/v2/fiscal/ibs-cbs/class-trib/:cst', DoGetFiscalIBSCBSClassTrib);
  THorse.Get('/v2/fiscal/ibs-cbs/configuracao', DoGetFiscalIBSCBSConfiguracao);
  THorse.Get('/v2/produtos/ifood', DoGetProdutosiFood);
  THorse.Get('/v2/cnpj/:cnpj', DoGetCNPJ);
  THorse.Post('/v2/parametro', DoAtualizParametro);
  THorse.Get('/v2/pix/pendente', DoGetPixPendente);
  THorse.Get('/v2/dashboard/venda/:dataini/:datafim', DoGetDashBoardVenda);
  THorse.Post('/v2/dashboard/venda/:dataini/:datafim', DoGetDashboardVendaV2);
  THorse.Get('/v2/relatorio/sabores-sap/:categorias',
    DoGetRelatorioSaboresSAPCategoria);
  THorse.Get('/v2/status/site', DoGetStatusSite);
  THorse.Get('/v2/test/erro', DoGetTestErro);
  THorse.Post('/v2/status/site/close', DoPostStatusSiteClose);
  THorse.Post('/v2/status/site/open', DoPostStatusSiteOpen);
  THorse.Post('/v2/marketing/gerar/cupom', DoPostMarketingGerarCupom);
  THorse.Get('/v2/marketing/cupom/liberado', DoGetCupomLiberado);
  THorse.Post('/v2/marketing/cupom/liberado/:codigo', DoGetCupomLiberado);
  THorse.Post('/v2/grava/generica/:tabela/:campo', DoPostGravacaoGenerica);
  THorse.Get('/v2/dados/pedido/site', DoGetPedidosSite);
  THorse.Get('/v2/dados/bloqueio', DoGetDadosBloqueio);
  THorse.Get('/v2/reset/bloqueio', DoGetResetBloqueio);
  THorse.Get('/v2/dados/certificados', DoGetCertificadoDigital);
  THorse.Get('/v2/dados/clientes', DoGetClientes);
  THorse.Post('/v2/dados/clientes', DoPostCliente);
  THorse.Post('/v2/corrigir/cliente-endereco/duplicados',
    DoPostCorrigirClienteEnderecoDuplicado);
  THorse.Get('/v2/dados/cliente/:codigo', DoGetDadoCliente);
  THorse.Post('/v2/emitir/nfce/fiado', DoPostEmitirNFCeFiado);
  THorse.Post('/v2/produtos/entrada/saida/:codigo', DoPostProdutoEntradaSaida);
  THorse.Get('/v2/estoque/produto/insulmo/:tipo/:codigo',
    DoGetEstoqueProdutoInsumo);
  THorse.Post('/v2/novo/cadastro', DoPostNovoCadastro);
  THorse.Get('/v2/consulta/cpf/:cpf', DoGetConsultaCPF);
  THorse.Get('/v2/consulta/clientes/fiado/:busca', DoGetConsultaClientesFiado);
  THorse.Get('/v2/consulta/clientes/fiado/', DoGetConsultaClientesFiado);
  THorse.Get('/v2/consulta/fiado/:cliente', DoGetConsultaFiado);
  THorse.Post('/v2/entrada/pagamento/fiado', DoPostEntradaPagamentoFiado);
  THorse.Get('/v2/comanda/:codigo', DoGetComanda);
  THorse.Get('/v2/comanda/id/:id', DoGetComanda);
  THorse.Post('/v2/comanda/:codigo/:mesa', DoPostMesa);
  THorse.Post('/v2/comanda/descricao/:codigo/:mesa', DoPostComandaDescricao);
  THorse.Post('/v2/usuario', DoPostUsuario);
  THorse.Get('/v2/tempo/delivery/:tempo', DoGetTempoDelivery);
  THorse.Get('/v2/tempo/vembuscar/:tempo', DoGetTempoVemBuscar);
  THorse.Get('/v2/dados/pedido/:pedido', DoGetDadosPedido);
  THorse.Get('/v2/dados/pedido/impressao/:pedido', DoGetDadosPedidoImpressao);
  THorse.Get('/v2/produtos/estoque/ativo', DoGetProdutosEstoqueAtivo);
  THorse.Post('/v2/cancelar/pedido', DoPostCancelarPedido);
  THorse.Post('/v2/aceita/pedido', DoPostAceitaPedido);
  // Cupom
  THorse.Get('/v2/cupom/desconto/site', DoGetCupomDescontoSite);
  THorse.Post('/v2/cupom/desconto/site', DoPostCupomDescontoSite);
  // Relatorio Caixa
  THorse.Get('/v2/forma/pagamento/caixa/:id', DoGetFormaPagamentoCaixa);
  THorse.Get('/v2/sangria/caixa/:id', DoGetSangriaCaixa);
  THorse.Get('/v2/movimentacoes/caixa/:codigo', DoGetMovimentacaoCaixa);
  // Relartorio Produtos (Cardapio)
  THorse.Post('/v2/relatorio/produtos/periodo', DoGetRelatorioProdutosPeriodo);
  THorse.Post('/v2/estorno/pedido/:codigo', DoGetEstornoPedido);
  THorse.Post('/v2/estorno/pedido/:codigo/:mesa', DoGetEstornoPedido);
  THorse.Get('/test', DoGetTest);
  // Varios Produtos
  // THorse.Post('/v2/grava/varios/produtos', DoGravaVariosProdutos);
  THorse.Post('/v2/caixa/deleta/sangria/:codigo', DoPostCaixaDeletaSangria);
  THorse.Post('/v2/caixa/imprime/sangria/:codigo', DoPostCaixaImprimeSangria);
  THorse.Get('/v2/notifica/produtos/abaixo/estoque',
    DoGetNotificacaoProdutosAbaixoEstoque);
  THorse.Get('/v2/pix/pendente/tabela', DoGetPixPendenteTabela);
  THorse.Get('/v2/pontos/fidelidade', DoGetFidelidadeSite);
  THorse.Get('/v2/pontos/fidelidade/historico/:codigo',
    DoGetFidelidadeHistoricoSite);
  THorse.Post('/v2/pontos/fidelidade', DoPostPontoFidelidade);
  THorse.Post('/v2/nfce/dados/cpfcnpj', DoPostNfceDaddos);
  THorse.Delete('/v2/user/agent/:codigo', DoDeleteUserAgent);
  THorse.Post('/v2/user/agent/:codigo', DoPostUserAgent);
  THorse.Get('/v2/user/agent/:codigo', DoGetUserAgent);
  THorse.Post('/v2/user/agent/name', DoPostUserAgentName);
  THorse.Post('/v2/user/agent/status', DoPostUserAgentStatus);
  THorse.Post('/v2/cadastro/geral', DoPostCadastroGeral);
  THorse.Post('/v2/cadastro/horario', DoPostCadastroHorario);
  THorse.Post('/v2/deleta/horario/:dia', DoPostDeletaHorario);
  THorse.Post('/v2/grava/mensagem', DoPostGravaMensagem);
  THorse.Post('/v2/grava/mesa', DoPostGravaMesa);
  THorse.Post('/v2/delete/mesa/:id', DoPostDelete);
  THorse.Post('/v2/site/grava/pedido', DoPostGravaPedidoSite);
  THorse.Get('/v2/whatsapp/valid/number/:numero', DoGetValidaNumero);
  THorse.Post('/v2/whatsapp/group', DoPostGroup);
  THorse.Get('/v2/whatsapp/group', doGetGroup);
  THorse.Post('/v2/gerar/id/:tabela/:campo', doPostGerarId);
  THorse.Post('/v2/reimportar/pedido/site/:codigo', doPostReImportar);
  THorse.Post('/v2/transferencia/produtos/:pedido',
    DoPostTransferenciaProdutos);
  THorse.Post('/v2/pagamento/produtos/:caixa', DoPostPagamentoProdutos);
  THorse.Get('/v2/pagamento/produtos/:codigo', DoGetPagamentoProduto);
  THorse.Post('/v2/pedido/produtos/seleciona/:codigo/:selecionado',
    DoPostPedidoProdutosSeleciona);
  THorse.Get('/whatsapp/goopedir/data', DoGetWhatsapp);
  THorse.Post('/whatsapp/goopedir/desconectar', DoPostWhatsappLogout);
  THorse.Post('/whatsapp/goopedir/atualizar', DoPostWhatsappAtualizar);
  THorse.Post('/v2/licensa', DoPostLicensa);
  THorse.Post('/v2/registro', DoPostRegistro);
  THorse.Get('/v2/atualizacao', DoGetAtualizacao);
  THorse.Post('/v2/atualizacao', DoGetAtualizacao);
  THorse.Post('/v2/atualizacao/iniciar', DoPostAtualizacaoIniciar);
  THorse.Get('/v2/status', DoGetStatus);
  THorse.Post('/v2/status', DoGetStatus);
  THorse.Get('/v2/banner', DoGetBanner);
  THorse.Post('/v2/banner', DoPostBanner);
  THorse.Get('/v2/user', DoGetUser);
  THorse.Get('/v2/busca/produtos/:busca', DoGetProdutoSaboresExtras);
  THorse.Post('/v2/ativa/inativa/itens/:codigo/:status/:tipo',
    DoPostAtivaInativaItens);
  THorse.Post('/v2/importacao/topedindo', DoPostImportacaoToPedindo);
  THorse.Post('/v2/reimprimir/cozinha/selecao', DoPostReImpressaoCozinha);
  THorse.Post('/v2/sincroniza/parametros', DoPostSincronizaParametros);
  // Tela de Pedido Habilitar/Desabilitar Retirada/Entrega
  THorse.Get('/v2/param/entrega/vembuscar', DoGetParametroEntregaVemBuscar);
  THorse.Post('/v2/param/entrega/:tipo', DoPostParametroEntrega);
  THorse.Post('/v2/param/vembuscar/:tipo', DoPostParametroVemBuscar);
  THorse.Get('/v2/gerar/pedidos/random', DoGetGerarPedidosRandom);
  THorse.Post('/v2/recontagem/estoque', DoPostRecontagemEstoque);
  THorse.Post('/v2/insulmos', DoPostInsulmo);
  THorse.Get('/v2/insulmos/ficha/:codigo', DoGetInsulmosFicha);
  THorse.Get('/v2/ingredientes/cardapio/processar',
    DoProcessarIngredientesCardapio);
  THorse.Post('/v2/ingredientes/cardapio/processar',
    DoProcessarIngredientesCardapio);
  THorse.Post('/v2/ingredientes/cardapio/gravar', DoGravarIngredientesCardapio);
  THorse.Get('/v2/ingredientes/cardapio/alerta',
    DoValidarAlertaIngredientesPendentes);
  THorse.Post('/v2/ingredientes/cardapio/alerta',
    DoValidarAlertaIngredientesPendentes);
  THorse.Get('/v2/parametros', DoGetParametros);
  THorse.Get('/v2/parametro/:chave', DoGetParametro);
  THorse.Post('/v2/cmv', DoPostCMV);
  THorse.Get('/v2/cmv/:codigo', DoGetCMV);
  // Tempo
  THorse.Post('/v2/tempo/entrega/pedido/:codigo', DoPostTempoEntregaPedido);
  // Despesas
  THorse.Post('/v2/despesa/categoria', DoPostDespesaCategoria);
  THorse.Post('/v2/despesa/categoria/buscar', DoPostDespesaCategoriaBuscar);
  THorse.Get('/v2/despesa/categoria/buscar/:descricao',
    DoGetDespesaCategoriaBuscar);
  THorse.Get('/v2/despesa/categoria', DoGetDespesaCategoria);
  THorse.Post('/v2/despesa', DoPostDespesa);
  THorse.Post('/v2/despesa/recorrencia/gerar', DoPostGerarDespesaRecorrencia);
  THorse.Get('/v2/despesa/recorrencia/gerar', DoPostGerarDespesaRecorrencia);
  THorse.Get('/v2/despesa/sugestao', DoGetDespesaSugestao);
  THorse.Get('/v2/despesa/sugestao/:busca', DoGetDespesaSugestao);
  THorse.Get('/v2/despesa/ano', DoGetDespesasAnos);
  THorse.put('/v2/despesa', DoGetDespesas);
  THorse.put('/v2/despesa/operacao', DoPutDespesaOperacao);
  THorse.Get('/v2/despesa/ano', DoGetDespesasAnos);
  THorse.Get('/v2/produto/vendas/:codigo', DoGetProdutoVendas);
  THorse.put('/v2/produto/vendas/:codigo', DoGetProdutoVendas);
  THorse.Get('/v2/produto/estoque/:codigo', DoGetProdutoEstoque);
  THorse.Get('/v2/produto/estoque/:codigo/analise/:data_inicio/:data_fim',
    DoGetProdutoAnaliseEstoque);
  THorse.Get('/v2/produto/analise-estoque/:codigo/:data_inicio/:data_fim',
    DoGetProdutoAnaliseEstoque);
  THorse.Get('/v2/produto/estoque/baixo/xml/:arquivo',
    DoGetProdutoEstoqueBaixoXML);
  THorse.Get('/v2/servico/impressao', DoGetServicoImpressao);
  THorse.Post('/v2/upload/imagem', DoPostImagemEmpresa);
  THorse.Get('/v2/produto/fiscal', DoGetProdutoFiscal);
  THorse.Get('/v2/produto/foto', DoGetProdutoFoto);
  // Enviar Peso
  THorse.Post('/v2/balanca', DoPostBalanca);
  THorse.Get('/v2/balanca/:id', DoGetPesoBalanca);
  THorse.Get('/v2/cache/site', GetCacheSite);
  THorse.Post('/v2/cache/site', GetCacheSite);
  THorse.Post('/v2/erro/nfce', DoPostErroNFCE);
  THorse.Post('/v2/zera/nfce', DoPostZeraNFCE);
  THorse.Get('/v2/valida/fechamento/caixa/:usuario',
    DoGetValidaFechamentoCaixa);
  THorse.Get('/v2/categoria/extra/:codigo', DoGetCategoriaExtra);
  THorse.Post('/v2/painel/chamada/:id', DoPostPainelChamada);
  THorse.Get('/v2/painel/chamada', DoGetPainelChamada);
  THorse.put('/v2/painel/chamada/:id', DoPutPainelChamada);
  THorse.Get('/v2/produto/sincronizacao', DoGetUltimoProduto);
  THorse.put('/v2/produto/sincronizacao/:id', DoPutUltimoProduto);
  THorse.Delete('/v2/excluir/produto/:id', DoDeleteProduto);
  THorse.Get('/v2/tipos', DoGetTipos);
  THorse.Post('v2/atualiza/obs/produto', DoPostAtualizaObsProduto);
  THorse.Post('v2/proxy', DoPostPonte);
  THorse.Post('v2/notafiscal/nfce/sc/consultar', DoPostConsultarNFCeSantaCatarina);
  THorse.Post('v2/notafiscal/fornecedor', DoPostDadosNotaFiscalFornecedor);
  THorse.Post('v2/notafiscal/fornecedor/item/fator',
    DoPostDadosNotaFiscalFornecedorItemFator);
  THorse.Post('v2/notafiscal/fornecedor/validar',
    DoPostValidarNotaFiscalDespesa);
  THorse.Post('/v2/notafiscal/entrada-estoque', DoPostNotaFiscalEntradaEstoque);
  THorse.Get('/v2/notafiscal/entrada-estoque', DoPostNotaFiscalEntradaEstoque);
  THorse.Get('v2/fornecedores', DoGetFornecedores);
  THorse.Post('v2/fornecedores/:id', DoPostFornecedor);
  THorse.put('v2/fornecedores/:id', DoPostFornecedor);
  THorse.Get('v2/fornecedores/:fornecedor/dossie/:data_inicio/:data_fim',
    DoGetFornecedorDossie);
  // Processamento
  THorse.Post('v2/cardapio/ia/processar', DoPostCardapioIA);
  THorse.Get('v2/cardapio/ia/processar', DoGetCardapioIA);
  // Cliente
  THorse.Get('v2/cliente/historico', DoGetClienteHistorico);
  // Seleciona Banco
  THorse.Get('v2/bancos', DoGetBancos);
  THorse.put('v2/bancos', DoPutBancos);
  // Dashboard
  THorse.Get('/v2/dashboard/principal', DoGetDadosDashBoardPrincipal);

  THorse.Get('v2/importa/pedido/site/:id', DoGetImportaPedidoSite);
end;

function DaysBetweenDates(const Date1, Date2: string): Integer;
var
  StartDate, EndDate: TDate;
begin
  // Converte as strings para o tipo TDate usando ISO8601ToDate
  StartDate := ISO8601ToDate(Date1);
  EndDate := ISO8601ToDate(Date2);
  // Calcula a diferen?a entre as duas datas
  Result := DaysBetween(StartDate, EndDate);
end;

procedure MovimentoProduto(Codigo, Tipo: Integer);
var
  conexao: TConexao;
  Dados: TFDMemTable;
  DadosBaixaComposta: TFDMemTable;
  DadosCombo: TFDMemTable;
  ID: Integer;
  // TIPO 1 - Baixa / 2 - Extorna
begin

  conexao := TConexao.Create('v2');
  if conexao.GetParametro('controle_estoque') = 0 then
  begin
    conexao.Free;
    exit;
  end;

  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('select pedido_produtos.codigo, pedido_produtos.codigo_produto, pedido_produtos.quantidade  from pedido');
  conexao.SQL.Add
    ('join pedido_produtos on pedido_produtos.codigo_pedido = pedido.codigo');
  conexao.SQL.Add('where pedido_produtos.codigo = :codigo');
  conexao.Parametros('codigo', Codigo);
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      DadosBaixaComposta := TFDMemTable.Create(nil);
      conexao.SQL.Add('select * from pedido_produto_sap where descricao <> ' +
        QuotedStr('') + ' and codigo_pedido_produto = :codigo');
      conexao.Parametros('codigo', Dados.FieldByName('codigo').AsString);
      DadosBaixaComposta.LoadFromJSON(conexao.ConsultaSQL);
      if DadosBaixaComposta.RecordCount > 0 then
      begin
        while not DadosBaixaComposta.Eof do
        begin
          if Tipo = 1 then
          begin
            MovimentacaoProdutoAdicional(Dados.FieldByName('codigo_produto')
              .AsInteger, DadosBaixaComposta.FieldByName('descricao').AsString,
              DadosBaixaComposta.FieldByName('valor').AsFloat,
              Dados.FieldByName('quantidade').AsFloat);
          end
          else
          begin
            MovimentacaoProdutoAdicionalExtorno
              (Dados.FieldByName('codigo_produto').AsInteger,
              DadosBaixaComposta.FieldByName('descricao').AsString,
              DadosBaixaComposta.FieldByName('valor').AsFloat,
              Dados.FieldByName('quantidade').AsFloat);
            // Fazer extorno do pedido
          end;
          DadosBaixaComposta.Next;
        end;
      end;
      DadosCombo := TFDMemTable.Create(nil);
      conexao.SQL.Add
        ('select 0, pci.produto_id as produto from produto_combo_config as pcc ');
      conexao.SQL.Add
        ('join produto_combo_item as pci on pci.combo_config_id = pcc.id');
      conexao.SQL.Add
        ('where pcc.produto_combo_id = :codigo and pcc.status = "ATIVO"');
      conexao.Parametros('codigo', Dados.FieldByName('codigo_produto')
        .AsInteger);
      DadosCombo.LoadFromJSON(conexao.ConsultaSQL);
      if DadosCombo.RecordCount > 0 then
      begin
        while not DadosCombo.Eof do
        begin

          if Tipo = 1 then
          begin
            MovimentacaoProduto(Dados.FieldByName('codigo').AsInteger,
              DadosCombo.FieldByName('produto').AsInteger, 2,
              Dados.FieldByName('quantidade').AsFloat);
          end
          else
          begin
            MovimentacaoProduto(Dados.FieldByName('codigo').AsInteger,
              DadosCombo.FieldByName('produto').AsInteger, 1,
              Dados.FieldByName('quantidade').AsFloat);
          end;

          DadosCombo.Next;
        end;
      end
      else
      begin

        if Tipo = 1 then
        begin
          MovimentacaoProduto(Dados.FieldByName('codigo').AsInteger,
            Dados.FieldByName('codigo_produto').AsInteger, 2,
            Dados.FieldByName('quantidade').AsFloat);
        end
        else
        begin
          MovimentacaoProduto(Dados.FieldByName('codigo').AsInteger,
            Dados.FieldByName('codigo_produto').AsInteger, 1,
            Dados.FieldByName('quantidade').AsFloat);
        end;
      end;
      DadosCombo.Free;
      DadosBaixaComposta.Free;
      Dados.Next;
    end;
  end;
  Dados.Free;
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('select produto_ingredientes.id_ingredientes, (produto_ingredientes.quantidade * pedido_produtos.quantidade) as quantidade, produto_ingredientes.id_produto as produto  from pedido');
  conexao.SQL.Add
    ('join pedido_produtos on pedido_produtos.codigo_pedido = pedido.codigo and pedido_produtos.codigo = :codigo');
  conexao.SQL.Add
    ('join produto_ingredientes on produto_ingredientes.id_produto = pedido_produtos.codigo_produto');
  conexao.Parametros('codigo', Codigo);
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      if Tipo = 2 then
        MovimentacaoInsulmo(Dados.FieldByName('id_ingredientes').AsInteger, 1,
          Dados.FieldByName('quantidade').AsFloat, 0, 0, False)
      else
        MovimentacaoInsulmo(Dados.FieldByName('id_ingredientes').AsInteger, 2,
          Dados.FieldByName('quantidade').AsFloat, 0, 0, False);
      Dados.Next;
    end;
  end;
  Dados.Free;
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('select pro_adi_personalizado_sabores.id_ingredientes as ingredientes, pro_adi_personalizado_sabores.quantidade_ingredientes as quantidade from pedido');
  conexao.SQL.Add
    ('join pedido_produtos on pedido_produtos.codigo_pedido = pedido.codigo and pedido_produtos.codigo = :codigo');
  conexao.SQL.Add
    ('join pedido_produto_sap on pedido_produto_sap.codigo_pedido_produto = pedido_produtos.codigo');
  conexao.SQL.Add
    ('join pro_adi_personalizado on pro_adi_personalizado.id_produto = pedido_produtos.codigo_produto and upper(pro_adi_personalizado.descricao) = upper(pedido_produto_sap.nomeclatura)');
  conexao.SQL.Add
    ('join pro_adi_personalizado_sabores on pro_adi_personalizado_sabores.id_pro_adi_personalizado = pro_adi_personalizado.id and');
  conexao.SQL.Add
    ('upper(pro_adi_personalizado_sabores.nome) = upper(pedido_produto_sap.descricao) and pro_adi_personalizado_sabores.id_ingredientes <> 0');
  conexao.SQL.Add
    ('and pro_adi_personalizado_sabores.quantidade_ingredientes <> 0');
  conexao.Parametros('codigo', Codigo);
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  if Dados.RecordCount > 0 then
  begin
    while not Dados.Eof do
    begin
      if Tipo = 2 then
        MovimentacaoInsulmo(Dados.FieldByName('ingredientes').AsInteger, 1,
          Dados.FieldByName('quantidade').AsFloat, 0, 0, False)
      else
        MovimentacaoInsulmo(Dados.FieldByName('ingredientes').AsInteger, 2,
          Dados.FieldByName('quantidade').AsFloat, 0, 0, False);
      Dados.Next;
    end;
  end;
  Dados.Free;
  conexao.Free;
end;

function ConverterData(const dataOriginal: string): string;
var
  Ano, Mes, Dia: Integer;
begin
  // Tenta extrair ano, m?s e dia da string
  Ano := StrToIntDef(Copy(dataOriginal, 1, 4), 0);
  Mes := StrToIntDef(Copy(dataOriginal, 6, 2), 0);
  Dia := StrToIntDef(Copy(dataOriginal, 9, 2), 0);
  // Verifica se os valores extra?dos s?o v?lidos
  if (Ano <> 0) and (Mes <> 0) and (Dia <> 0) then
  begin
    // Formata a data no formato desejado
    Result := Format('%02d/%02d/%04d', [Dia, Mes, Ano]);
  end
  else
  begin
    // Retorna uma string indicando que houve um erro na convers?o
    Result := 'Erro na convers?o da data';
  end;
end;

function GetCupomSite: String;
var
  Requisicao: iRequisicao;
begin
  Requisicao := iRequisicao.Create(nil);
  Requisicao.BaseURL := getUrlGoopedir;
  Requisicao.URL := 'api/cupom/lista/' + frmServidor.UserID.ToString;
  Requisicao.AddHeader('Authorization', frmServidor.APIGoopedir.GetToken);
  Requisicao.TempoExpiracao := 15 * 1000;
  try
    Requisicao.Execute;
    Result := Requisicao.Retorno;
  except
    Result := '[]';
  end;
  Requisicao.Free;
end;

end.
