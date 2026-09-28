unit nfce;

interface

uses Horse, JOSE.Core.JWT, JOSE.Core.Builder, SysUtils, Horse.JWT, uDM,
  FireDAC.Comp.Client, Dataset.Serialize, JSON, token.autorizacao,
  Data.FireDACJSONReflect, Soap.EncdDecd, FMX.Graphics, FMX.Printer, uGlobais,
  uRequisicao, System.RegularExpressions, REST.Client, REST.Types, uNFCe;

procedure Registry;

procedure DeletarNFCe(CNPJ, Chave: String);

function BuscaDadosFornecedor(DataIni, DataFim: String): String;

implementation

uses FireDAC.Stan.Option, token, conexao, JOSE.Types.JSON, System.Classes,
  Data.DB, IdWinsock2, Vcl.Dialogs, Vcl.ExtCtrls, Horse.Upload, System.Types,
  Winapi.Windows, uMain, System.StrUtils, Vcl.StdCtrls, util, uSite;

function JsonNumberField(Field: TField): TJSONNumber;
var
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Invariant;
  Result := TJSONNumber.Create(FormatFloat('0.######', Field.AsFloat, Fmt));
end;

function BuscaDadosFornecedor(DataIni, DataFim: String): String;
var
  conexao: TConexao;
  Retorno: TJSONArray;
  Fornecedor: TJSONObject;
  NotasFiscais: TJSONArray;
  Notafiscal: TJSONObject;
  Itens: TJSONArray;
  Item: TJSONObject;

  Dados: TFDMemTable;
  DadosNotas: TFDMemTable;
  DadosNotasItem: TFDMemTable;
begin

  conexao := TConexao.Create('Notas');
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add('select * from fornecedor');
  Dados.LoadFromJSON(conexao.ConsultaSQL);
  Retorno := TJSONArray.Create;
  while not Dados.Eof do
  begin

    Fornecedor := TJSONObject.Create;
    Fornecedor.AddPair('id', Dados.FieldByName('id').AsString);
    Fornecedor.AddPair('cnpj', Dados.FieldByName('cnpj').AsString);
    Fornecedor.AddPair('nome', UpperCase(Dados.FieldByName('nome').AsString));

    conexao.SQL.Add
      ('select id, serie, numero, chave,modelo,tipo,data_emissao as emissao, vNF, status_importacao from nota_fiscal where fornecedor_id = :fornecedor');
    if DataIni <> '' then
    begin
      conexao.SQL.Add(' AND data_emissao >= "' + DataIni + '"');
    end;
    if DataFim <> '' then
    begin
      conexao.SQL.Add(' AND data_emissao <= "' + DataFim + '"');
    end;
    conexao.Parametros('fornecedor', Dados.FieldByName('id').AsString);
    DadosNotas := TFDMemTable.Create(nil);
    DadosNotas.LoadFromJSON(conexao.ConsultaSQL);
    NotasFiscais := TJSONArray.Create;
    while not DadosNotas.Eof do
    begin
      Notafiscal := TJSONObject.Create;
      Notafiscal.AddPair('chave', DadosNotas.FieldByName('chave').AsString);
      Notafiscal.AddPair('serie', DadosNotas.FieldByName('serie').AsString);
      Notafiscal.AddPair('numero', DadosNotas.FieldByName('numero').AsString);
      Notafiscal.AddPair('modelo', DadosNotas.FieldByName('modelo').AsString);
      Notafiscal.AddPair('tipo', DadosNotas.FieldByName('tipo').AsString);
      Notafiscal.AddPair('emissao', DadosNotas.FieldByName('emissao').AsString);
      Notafiscal.AddPair('valor', DadosNotas.FieldByName('vNF').AsString);
      Notafiscal.AddPair('status', DadosNotas.FieldByName('status_importacao')
        .AsString);

      DadosNotasItem := TFDMemTable.Create(nil);
      // conexao.SQL.Add('select * from nota_fiscal_item where nota_fiscal_id = :nota');
      conexao.SQL.Add
        ('select nfi.*, fi.id as fornecedor_item_id, fi.codigo_vinculo, fi.campo_vinculo, fi.fator, fi.tabela_vinculo,');
      conexao.SQL.Add
        ('case when fi.tabela_vinculo = "produto" then upper(p.nome_produto) when fi.tabela_vinculo = "ingrediente" then upper(i.descricao) else null end as insumo_nome,');
      conexao.SQL.Add
        ('case when fi.tabela_vinculo = "produto" then upper(p.un) when fi.tabela_vinculo = "ingrediente" then upper(i.unidade) else null end as insumo_unidade,');
      conexao.SQL.Add
        ('case when fi.tabela_vinculo = "produto" then p.saldo_atual when fi.tabela_vinculo = "ingrediente" then i.saldo else null end as saldo_atual');
      conexao.SQL.Add('from nota_fiscal_item nfi');
      conexao.SQL.Add
        ('left join fornecedor_item fi on fi.id = nfi.fornecedor_item_id');
      conexao.SQL.Add
        ('left join produto p on fi.tabela_vinculo = "produto" and p.codigo = fi.codigo_vinculo');
      conexao.SQL.Add
        ('left join ingredientes i on fi.tabela_vinculo = "ingrediente" and i.id = fi.codigo_vinculo');
      conexao.SQL.Add('where nfi.nota_fiscal_id = :nota');

      conexao.Parametros('nota', DadosNotas.FieldByName('id').AsString);
      DadosNotasItem.LoadFromJSON(conexao.ConsultaSQL);
      Itens := TJSONArray.Create;
      while not DadosNotasItem.Eof do
      begin
        Item := TJSONObject.Create;
        Item.AddPair('cProd', DadosNotasItem.FieldByName('cProd').AsString);
        Item.AddPair('xProd', DadosNotasItem.FieldByName('xProd').AsString);
        Item.AddPair('NCM', DadosNotasItem.FieldByName('NCM').AsString);
        Item.AddPair('qCom', DadosNotasItem.FieldByName('qCom').AsString);
        Item.AddPair('valor', DadosNotasItem.FieldByName('vTotal').AsString);
        Item.AddPair('UN', DadosNotasItem.FieldByName('uTrib').AsString);
        Item.AddPair('fornecedor_item_id', DadosNotasItem.FieldByName
          ('fornecedor_item_id').AsString);
        Item.AddPair('fator', JsonNumberField(DadosNotasItem.FieldByName('fator')));
        Item.AddPair('vinculo', DadosNotasItem.FieldByName('codigo_vinculo')
          .AsString);
        Item.AddPair('codigo_vinculo', DadosNotasItem.FieldByName
          ('codigo_vinculo').AsString);
        Item.AddPair('campo_vinculo', DadosNotasItem.FieldByName
          ('campo_vinculo').AsString);
        Item.AddPair('tabela_vinculo', DadosNotasItem.FieldByName
          ('tabela_vinculo').AsString);
        Item.AddPair('insumo_nome', DadosNotasItem.FieldByName
          ('insumo_nome').AsString);
        Item.AddPair('insumo_unidade', DadosNotasItem.FieldByName
          ('insumo_unidade').AsString);
        Item.AddPair('saldo_atual', JsonNumberField(DadosNotasItem.FieldByName
          ('saldo_atual')));
        if DadosNotasItem.FieldByName('tabela_vinculo').AsString = 'ingrediente'
        then
          Item.AddPair('tipo', 2)
        else if DadosNotasItem.FieldByName('tabela_vinculo').AsString = 'produto'
        then
          Item.AddPair('tipo', 1)
        else
          Item.AddPair('tipo', 0);
        Itens.AddElement(Item);
        DadosNotasItem.Next;
      end;

      DadosNotasItem.Free;

      Notafiscal.AddPair('itens', Itens);
      NotasFiscais.AddElement(Notafiscal);
      DadosNotas.Next;
    end;
    DadosNotas.Free;

    Fornecedor.AddPair('notas', NotasFiscais);
    Retorno.AddElement(Fornecedor);
    Dados.Next;
  end;
  Result := Retorno.ToString;
  Retorno.Free;
  conexao.Free;
  Dados.Free;
end;

procedure DoGetPedidoOutros(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJSONArray>(GetComplemento(Req.Params['codigo'].ToInteger));
end;

procedure DoGetProdutosPedido(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJSONArray>(GetProdutos(Req.Params['codigo'].ToInteger));
end;

procedure DoGetPedidoPagamento(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJSONArray>(GetPagamento(Req.Params['codigo'].ToInteger));
end;

procedure DoGetNumeroNota(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  Codigo: Integer;
begin
  conexao := TConexao.Create('nfce');
  try
    Codigo := ProximoNumeroNFCe(conexao);
    Res.Send(Codigo.ToString);
  finally
    conexao.Free;
  end;
end;

procedure DoGetNumeroLote(Req: THorseRequest; Res: THorseResponse; Next: TProc);
Var
  Serie: String;
  conexao : TConexao;
begin
  conexao := TConexao.Create('DoGetNumeroLote');
  try
    Serie := conexao.GetParametro('nfce_serie')
  except
    Serie := '1';
  end;
  conexao.Free;

  Res.Send(Serie);

end;

procedure DOGetNFCeEmissao(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');

  conexao.SQL.Add
    ('update pedido set nfce_emite = 1 where data_pedido = curdate() and nfce_chave = "CONTING�NCIA"');
  conexao.ExecuteSQL;
  conexao.SQL.Add
    ('SELECT * FROM pedido WHERE nfce_emite = 1 and id_caixa > 0  AND status > 0  AND data_pedido >= '
    + QuotedStr('2024-09-01') +
    ' and codigo_pedido_dia > 0 and data_pedido >= DATE_FORMAT(CURDATE(), "%Y-%m-01")');
  Res.Send<TJSONArray>(conexao.ConsultaSQL);
  conexao.Free;
end;

procedure DoPostNotaSinc(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  DadosNF: TFDMemTable;
  Codigo: Integer;
  JSON: TJSONObject;
begin
  DadosNF := TFDMemTable.Create(nil);
  conexao := TConexao.Create('nfce');
  conexao.SQL.Add
    ('update pedido set nfce_sinc_contabilidade = 1 where nfce_chave = :nfce_chave');
  conexao.Parametros('nfce_chave', Req.Params['chave']);
  conexao.ExecuteSQL;

  conexao.SQL.Add('select * from pedido where nfce_chave = :nfce_chave');
  conexao.Parametros('nfce_chave', Req.Params['chave']);
  DadosNF.LoadFromJSON(conexao.ConsultaSQL);

  JSON := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;

  if Assigned(JSON) then
  begin

    if DadosNF.RecordCount > 0 then
    begin
      conexao.SQL.Add('delete from pedido_nfce where id_pedido = :pedido');
      conexao.Parametros('pedido', DadosNF.FieldByName('codigo').AsInteger);
      conexao.ExecuteSQL;

      Codigo := conexao.GerarID('pedido_nfce', 'id');
      conexao.SQL.Add
        ('insert into pedido_nfce (id,id_pedido,chave,protocolo,caminho,path) values (:id,:id_pedido,:chave,:protocolo,:caminho,:path)');
      conexao.Parametros('id', Codigo);
      conexao.Parametros('id_pedido', DadosNF.FieldByName('codigo').AsInteger);
      conexao.Parametros('chave', DadosNF.FieldByName('nfce_chave').AsString);
      conexao.Parametros('protocolo', DadosNF.FieldByName('nfce_protocolo')
        .AsString);
      conexao.Parametros('path', JSON.GetValue('path').Value);
      conexao.Parametros('caminho', JSON.GetValue('caminho').Value);
      conexao.ExecuteSQL;

    end;

  end;

  DadosNF.Free;

  conexao.Free;
end;

procedure DoPostEmissaoNFCe(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  Chave: String;

  path: String;
begin
  conexao := TConexao.Create('nfce');

  if (Req.Params['chave'] = 'CANCELADA') then
  begin
    conexao.SQL.Add
      ('select 0 as zero, nfce_chave from pedido where codigo = :codigo');
    conexao.Parametros('codigo', Req.Params['codigo']);
    Chave := conexao.FieldByName('nfce_chave');
    DeletarNFCe(conexao.GetParametro('cnpj'), Chave);
  end
  else
  begin
    frmServidor.memErrosNFCE.Close;
    frmServidor.memErrosNFCE.Open;

    if frmServidor.memErrosNFCE.RecordCount > 0 then
    begin
      if frmServidor.memErrosNFCE.Locate('pedido', Req.Params['codigo']) then
      begin
        frmServidor.memErrosNFCE.Delete;
        frmServidor.memErrosNFCE.Last;
      end;
    end;

    conexao.SQL.Add
      ('select 0, nfce_imprimir from pedido where codigo = :codigo');
    conexao.Parametros('codigo', Req.Params['codigo']);
    try
      if conexao.FieldByName('nfce_imprimir') = '1' then
      begin
        conexao.SQL.Add
          ('insert into impressao_pedido_nfce (id_pedido) values (:codigo)');
        conexao.Parametros('codigo', Req.Params['codigo']);
        conexao.ExecuteSQL;
      end;

    except

    end;

  end;

  conexao.SQL.Add
    ('UPDATE pedido SET nfce_status = "EMITIDA", nfce_emite = 0 WHERE (codigo = :codigo or pedido_nfce = :codigo)');
  conexao.Parametros('codigo', Req.Params['codigo']);
  conexao.ExecuteSQL;

  if (Req.Params['chave'] = 'CONTING�NCIA') then
  begin
    conexao.SQL.Add
      ('UPDATE pedido SET nfce_status = "CONTINGENCIA", nfce_emite = 0 WHERE (codigo = :codigo or pedido_nfce = :codigo);');
    conexao.Parametros('codigo', Req.Params['codigo']);
    conexao.ExecuteSQL;
  end;

  conexao.SQL.Add
    ('update pedido set nfce_hora = current_time, nfce_data = current_date, nfce_chave = :nfce_chave, nfce_protocolo = :nfce_protocolo, nfce_ambiente = :nfce_ambiente, nfce_numero = :nfce_numero, nfce_emite = 2 where (codigo = :codigo or pedido_nfce = :codigo)');
  conexao.Parametros('codigo', Req.Params['codigo']);
  conexao.Parametros('nfce_chave', Req.Params['chave']);
  conexao.Parametros('nfce_protocolo', Req.Params['protocolo']);
  conexao.Parametros('nfce_ambiente', Req.Params['ambiente']);
  conexao.Parametros('nfce_numero', Req.Params['numero']);

  conexao.ExecuteSQL;
  conexao.Free;

end;

procedure DoGetNotas(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');
  conexao.SQL.Add
    ('SELECT codigo, nfce_chave as chave FROM pedido where nfce_emite = 2 and DATE_FORMAT(data_pedido, "%Y%m") = "'
    + Req.Params['mes'] + '"');
  Res.Send<TJSONArray>(conexao.ConsultaSQL);

  conexao.Free;
end;

procedure DoGetNFceContabilidade(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
  Codigo: Integer;
begin
  conexao := TConexao.Create('nfce');
  Dados := TFDMemTable.Create(nil);
  conexao.SQL.Add('select * from contabilidade where data = :data');
  conexao.Parametros('data', FormatDateTime('yyyymm', IncMonth(date, -1)));
  Dados.LoadFromJSON(conexao.ConsultaSQL);

  if Dados.RecordCount = 0 then
  begin
    Codigo := conexao.GerarID('contabilidade', 'id');
    conexao.SQL.Add
      ('insert into contabilidade (id,data_envio,data,status) values (:id,current_date,:data,0)');
    conexao.Parametros('data', FormatDateTime('yyyymm', IncMonth(date, -1)));
    conexao.Parametros('id', Codigo);
    conexao.ExecuteSQL;
  end;
  conexao.SQL.Add('select * from contabilidade where data = :data');
  conexao.Parametros('data', FormatDateTime('yyyymm', IncMonth(date, -1)));
  Res.Send<TJSONArray>(conexao.ConsultaSQL);
  conexao.Free;
  Dados.Free;

end;

procedure DoGetNotasPendentesSinc(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');
  conexao.SQL.Add('select * from pedido where nfce_chave <> ' +
    QuotedStr('CANCELADA') +
    ' and nfce_sinc_contabilidade = 0 and nfce_ambiente = 1 and data_pedido > '
    + QuotedStr('2024-08-01'));
  Res.Send<TJSONArray>(conexao.ConsultaSQL);
  // Res.Send(conexao.SQL.Text);
  conexao.Free;
end;

procedure DoGetCode(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Send<TJSONArray>(frmServidor.EventNFC.ToJSONArray());

  frmServidor.EventNFC.Close;
end;

procedure DoPostCodeMotivo(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  Objec: TJSONObject;
  conexao: TConexao;
  Chave: String;
  Motivo: String;
begin
  conexao := TConexao.Create('nfce');
  Objec := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  Chave := Objec.GetValue('chave').Value;
  Motivo := Objec.GetValue('motivo').Value;
  conexao.SQL.Add
    ('update pedido set motivo_cancelamento = :motivo where nfce_chave = :chave');
  conexao.Parametros('motivo', Objec.GetValue('motivo').Value);
  conexao.Parametros('chave', Objec.GetValue('chave').Value);
  conexao.ExecuteSQL;
  conexao.Free;
  Objec.Free;
end;

procedure DoPostCode(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Objec: TJSONObject;
begin

  Objec := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  try
    if (Objec.GetValue('code').Value = '1') then
    begin
      ImprimirNFCeChave(Objec.GetValue('chave').Value);
    end else begin
      CancelarNFCe(Objec.GetValue('chave').Value,Objec.GetValue('obs').Value);
    end;
  finally
    Objec.Free;
  end;

  // if Objec.GetValue('code').Value = '1' then
  // begin
  // conexao := TConexao.Create('nfce');
  // conexao.SQL.Add
  // ('delete from impressao_pedido_nfce where id_pedido = :codigo');
  // conexao.Parametros('codigo', Objec.GetValue('id').Value);
  // conexao.ExecuteSQL;
  // conexao.SQL.Add
  // ('insert into impressao_pedido_nfce (id_pedido) values (:codigo)');
  // conexao.Parametros('codigo', Objec.GetValue('id').Value);
  // conexao.ExecuteSQL;
  // conexao.Free;
  // exit;
  // end;
  //
  // frmServidor.EventNFC.Insert;
  // frmServidor.EventNFC.FieldByName('CODE').AsString :=
  // Objec.GetValue('code').Value;
  // frmServidor.EventNFC.FieldByName('id').AsString := Objec.GetValue('id').Value;
  // frmServidor.EventNFC.FieldByName('CHAVE').AsString :=
  // Objec.GetValue('chave').Value;
  // frmServidor.EventNFC.FieldByName('OBS').AsString :=
  // Objec.GetValue('obs').Value;
  // frmServidor.EventNFC.Post;

end;

procedure DoPostNFceContabilidade(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('nfce');
  conexao.SQL.Add
    ('update contabilidade set status = :status, erro = :erro where data = :data');
  conexao.Parametros('data', FormatDateTime('yyyymm', IncMonth(date, -1)));
  conexao.Parametros('status', Req.Params['status']);
  conexao.Parametros('erro', Req.Params['msg']);
  conexao.ExecuteSQL;
  conexao.Free;
end;

procedure DeletarNFCe(CNPJ, Chave: String);
var
  RESTClient: TRESTClient;
  RESTRequest: TRESTRequest;
  RESTResponse: TRESTResponse;
begin
  RESTClient := TRESTClient.Create(API_NFCE + 'deletar.php');
  RESTRequest := TRESTRequest.Create(nil);
  RESTResponse := TRESTResponse.Create(nil);
  try
    RESTRequest.Client := RESTClient;
    RESTRequest.Response := RESTResponse;
    RESTRequest.Method := TRESTRequestMethod.rmPOST;
    // Adiciona os par�metros ao corpo da requisi��o
    RESTRequest.AddParameter('cnpj', CNPJ,
      TRESTRequestParameterKind.pkGETorPOST);
    RESTRequest.AddParameter('chaveNFCe', Chave,
      TRESTRequestParameterKind.pkGETorPOST);
    // Executa a requisi��o
    RESTRequest.Execute;
    // Verifica a resposta
    if RESTResponse.StatusCode = 200 then
    begin
      // ////////showmessage1('Resposta do servidor: ' + RESTResponse.Content);
    end
    else
    begin
      // ////////showmessage1('Erro na requisi��o. C�digo: ' + RESTResponse.StatusCode.ToString);
    end;
  finally
    RESTRequest.Free;
    RESTResponse.Free;
    RESTClient.Free;
  end;
end;

procedure DoPostDFESincronizar(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  JSONBody, JSONConsulta, JSONDocs, JSONDoc: TJSONObject;
  JSONArray: TJSONArray;
  idConsulta, idDoc: Integer;
  i: Integer;
begin
  conexao := TConexao.Create('nfce'); // usa o mesmo alias que tu j� tens
  JSONBody := nil;
  try
    JSONBody := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    if not Assigned(JSONBody) then
      raise Exception.Create('JSON inv�lido.');

    // --- Bloco "consulta" ---
    JSONConsulta := JSONBody.GetValue('consulta') as TJSONObject;
    idConsulta := conexao.GerarID('dfe_consulta', 'id');
    conexao.SQL.Add
      ('INSERT INTO dfe_consulta (id, cnpj_empresa, data_consulta, hora_consulta, ultimo_nsu, qtd_documentos, ambiente) '
      + 'VALUES (:id, :cnpj_empresa, curdate(), curtime(), :ultimo_nsu, :qtd_documentos, :ambiente)');
    conexao.Parametros('id', idConsulta);
    conexao.Parametros('cnpj_empresa', Req.Params['cnpj']);
    conexao.Parametros('ultimo_nsu', JSONConsulta.GetValue('ultimo_nsu').Value);
    conexao.Parametros('qtd_documentos',
      JSONConsulta.GetValue('qtd_documentos').Value);
    conexao.Parametros('ambiente', 'producao');
    conexao.ExecuteSQL;

    // --- Bloco "documentos" ---
    JSONArray := JSONBody.GetValue('documentos') as TJSONArray;
    if Assigned(JSONArray) then
    begin
      for i := 0 to JSONArray.Count - 1 do
      begin
        JSONDoc := JSONArray.Items[i] as TJSONObject;
        idDoc := conexao.GerarID('dfe_documento', 'id');
        conexao.SQL.Add
          ('INSERT INTO dfe_documento (id, id_consulta, nsu, chave, cnpj_emitente, nome_emitente, valor, data_emissao, situacao, xml_base64, tipo) '
          + 'VALUES (:id, :id_consulta, :nsu, :chave, :cnpj_emitente, :nome_emitente, :valor, :data_emissao, :situacao, :xml_base64, :tipo) '
          + 'ON DUPLICATE KEY UPDATE id_consulta = VALUES(id_consulta), nsu = VALUES(nsu), cnpj_emitente = VALUES(cnpj_emitente), '
          + 'nome_emitente = VALUES(nome_emitente), valor = VALUES(valor), data_emissao = VALUES(data_emissao), situacao = VALUES(situacao), '
          + 'xml_base64 = VALUES(xml_base64), tipo = VALUES(tipo)');
        conexao.Parametros('id', idDoc);
        conexao.Parametros('id_consulta', idConsulta);
        conexao.Parametros('nsu', JSONDoc.GetValue('nsu')
          .ToString.Replace('"', ''));
        conexao.Parametros('chave', JSONDoc.GetValue('chave')
          .ToString.Replace('"', ''));
        conexao.Parametros('cnpj_emitente', JSONDoc.GetValue('cnpj_emitente')
          .ToString.Replace('"', ''));
        conexao.Parametros('nome_emitente', JSONDoc.GetValue('emitente')
          .ToString.Replace('"', ''));
        conexao.Parametros('valor', JSONDoc.GetValue('valor')
          .ToString.Replace('"', ''));
        conexao.Parametros('data_emissao', JSONDoc.GetValue('data_emissao')
          .ToString.Replace('"', ''));
        conexao.Parametros('situacao', JSONDoc.GetValue('situacao')
          .ToString.Replace('"', ''));
        if Assigned(JSONDoc.GetValue('xml_base64')) then
          conexao.Parametros('xml_base64', JSONDoc.GetValue('xml_base64')
            .ToString.Replace('"', ''))
        else
          conexao.Parametros('xml_base64', '');

        conexao.Parametros('tipo', 'nfe');
        conexao.ExecuteSQL;
      end;
    end;

    Res.Send('Registros sincronizados com sucesso!');
  finally
    JSONBody.Free;
    conexao.Free;
  end;
end;

procedure DoConsultarDFe(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  CNPJ: String;
begin
  CNPJ := '';
  try
    CNPJ := Req.Params['cnpj'];
  except
  end;

  Res.Send<TJSONObject>(ConsultarDFeSefaz(CNPJ));
end;

procedure DoListarNotasDFeManifestacao(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicio, DataFim: string;
begin
  conexao := TConexao.Create('nfce');
  try
    DataInicio := Req.Params['data_inicio'];
    DataFim := Req.Params['data_fim'];
    conexao.SQL.Add('SELECT dfe.id, dfe.nsu, dfe.chave, dfe.cnpj_emitente, ' +
      'dfe.nome_emitente, dfe.valor AS vNF, dfe.data_emissao, dfe.situacao, ' +
      'dfe.tipo, dfe.manifestada, dfe.manifestacao_tipo, dfe.manifestacao_status, ' +
      'dfe.manifestacao_origem, dfe.manifestacao_data, ' +
      'CASE WHEN IFNULL(dfe.xml_base64, "") <> "" THEN 1 ELSE 0 END AS xml_disponivel, ' +
      'CASE WHEN dfe.tipo = "resumo" THEN 1 ELSE 0 END AS pode_manifestar, ' +
      'CASE WHEN nf.id IS NOT NULL THEN "sim" ELSE "nao" END AS importada ' +
      'FROM dfe_documento dfe ' +
      'LEFT JOIN nota_fiscal nf ON nf.chave COLLATE utf8mb4_general_ci = dfe.chave COLLATE utf8mb4_general_ci ' +
      'WHERE DATE(dfe.data_emissao) BETWEEN :data_inicio AND :data_fim ' +
      'ORDER BY dfe.data_emissao DESC');
    conexao.Parametros('data_inicio', DataInicio);
    conexao.Parametros('data_fim', DataFim);
    Res.Send<TJSONArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;
procedure DoManifestarDFe(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  Body: TJSONObject;
  Justificativa: String;
begin
  Justificativa := '';
  Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  try
    if Assigned(Body) and Assigned(Body.GetValue('justificativa')) then
      Justificativa := Body.GetValue('justificativa').Value;
  finally
    Body.Free;
  end;
  Res.Send<TJSONObject>(ManifestarDFePorChave(Req.Params['chave'],
    Req.Params['tipo'], Justificativa));
end;
procedure DoEventoDFe(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Body: TJSONObject;
  Chave, Tipo, Justificativa: String;
begin
  Chave := '';
  Tipo := '';
  Justificativa := '';
  Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  try
    if Assigned(Body) then
    begin
      if Assigned(Body.GetValue('chave')) then
        Chave := Body.GetValue('chave').Value;
      if Assigned(Body.GetValue('tipo')) then
        Tipo := Body.GetValue('tipo').Value;
      if (Tipo = '') and Assigned(Body.GetValue('metodo')) then
        Tipo := Body.GetValue('metodo').Value;
      if Assigned(Body.GetValue('justificativa')) then
        Justificativa := Body.GetValue('justificativa').Value;
    end;
  finally
    Body.Free;
  end;
  Res.Send<TJSONObject>(ManifestarDFePorChave(Chave, Tipo, Justificativa));
end;
procedure DoConsultarXMLDFePorChave(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJSONObject>(ConsultarXMLDFePorChave(Req.Params['chave']));
end;
procedure DoPostSimularImportacaoDFeArquivo(Req: THorseRequest;
  Res: THorseResponse; Next: TProc);
var
  Body: TJSONObject;
  Caminho: String;
begin
  Caminho := '';
  Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
  try
    if Assigned(Body) and Assigned(Body.GetValue('caminho')) then
      Caminho := Body.GetValue('caminho').Value;
  finally
    Body.Free;
  end;
  Res.Send<TJSONObject>(SimularImportacaoDFeArquivo(Caminho));
end;
procedure DoConsultarStatusServicoNFe(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJSONObject>(ConsultarStatusServicoNFe);
end;
procedure DoGetStatusServicoNFeGravado(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
begin
  Res.Send<TJSONObject>(MontarJSONStatusServicoNFeGravado);
end;
procedure DoGetUltimoNSU(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  Dados: TFDMemTable;
begin
  conexao := TConexao.Create('nfce');
  Dados := TFDMemTable.Create(nil);
  try
    conexao.SQL.Add
      ('SELECT ultimo_nsu FROM dfe_consulta WHERE cnpj_empresa = :cnpj ORDER BY id DESC LIMIT 1');
    conexao.Parametros('cnpj', Req.Params['cnpj']);
    Dados.LoadFromJSON(conexao.ConsultaSQL);
    if Dados.RecordCount > 0 then
      Res.Send(Dados.FieldByName('ultimo_nsu').AsString)
    else
      Res.Send('0');
  finally
    Dados.Free;
    conexao.Free;
  end;
end;

procedure DoGetNotasDFe(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  DataInicio, DataFim: string;
  SQL: string;
begin
  conexao := TConexao.Create('nfce'); // ou 'erp', se for outro alias
  try
    DataInicio := Req.Params['data_inicio'];
    DataFim := Req.Params['data_fim'];

    SQL := 'SELECT ' + '  dfe.id, ' + '  dfe.nsu, ' + '  dfe.chave, ' +
      '  dfe.cnpj_emitente, ' + '  dfe.nome_emitente, ' + '  dfe.valor AS vNF, '
      + '  dfe.data_emissao, dfe.manifestada, dfe.manifestacao_tipo, ' +
      '  dfe.manifestacao_status, dfe.manifestacao_origem, dfe.manifestacao_data, ' +
      '  CASE WHEN nf.id IS NOT NULL THEN "sim" ELSE "nao" END AS importada ' +
      'FROM dfe_documento dfe ' +
      'LEFT JOIN nota_fiscal nf ON nf.chave COLLATE utf8mb4_general_ci = dfe.chave COLLATE utf8mb4_general_ci '
      + 'WHERE DATE(dfe.data_emissao) BETWEEN :data_inicio AND :data_fim ' +
      'ORDER BY dfe.data_emissao DESC';
    conexao.SQL.Add(SQL);
    conexao.Parametros('data_inicio', DataInicio);
    conexao.Parametros('data_fim', DataFim);

    Res.Send<TJSONArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;

procedure DoVerificaConsulta(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  ambiente: string;
begin
  ambiente := Req.Params['ambiente'];
  if ambiente = '1' then
    ambiente := 'producao'
  else if ambiente = '2' then
    ambiente := 'homologacao';

  conexao := TConexao.Create('nfce');
  try
    conexao.SQL.Add('SELECT ' + '   dc.id, ' + '   dc.ultimo_nsu, ' +
      '   dc.data_consulta, ' + '   dc.hora_consulta, ' + '   CASE ' +
      '       WHEN TIMESTAMP(dc.data_consulta, dc.hora_consulta) <= NOW() - INTERVAL 1 HOUR '
      + '       THEN 1 ELSE 0 ' + '   END AS status ' + 'FROM dfe_consulta dc '
      + 'WHERE dc.ambiente = :ambiente ORDER BY dc.id DESC LIMIT 1');
    conexao.Parametros('ambiente', ambiente);

    Res.Send(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;

procedure DoGetNotasFiscais(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexaoNotas, conexaoItens: TConexao;
  Notas, Itens: TFDMemTable;
  JSONNotas, JSONItens, JSONNota: TJSONArray;
  NotaObj, Retorno: TJSONObject;
  DataInicio, DataFim: string;
begin
  Res.Send(BuscaDadosFornecedor(Req.Params['data_inicio'],
    Req.Params['data_fim']));

end;

procedure DoGetNFCeFila(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  conexao: TConexao;
  Limit: Integer;
  IntervaloReenvioMinutos: Integer;
begin
  try
    Limit := StrToIntDef(Req.Query['limit'], 10);
  except
    Limit := 10;
  end;
  if Limit <= 0 then
    Limit := 10;
  if Limit > 50 then
    Limit := 50;

  conexao := TConexao.Create('nfce');
  try
    IntervaloReenvioMinutos := StrToIntDef(
      conexao.GetParametro('nfce_reenvio_erro_minutos'), 10);
    if IntervaloReenvioMinutos <= 0 then
      IntervaloReenvioMinutos := 10;
    if IntervaloReenvioMinutos > 1440 then
      IntervaloReenvioMinutos := 1440;

    // 1) trava o lote
    conexao.SQL.Text := 'UPDATE pedido SET  nfce_status = "PROCESSANDO", ' +
      ' nfce_lock = NOW() WHERE nfce_emite = 1 ' +
      'AND (nfce_status = "" OR nfce_status is null OR nfce_status = "PENDENTE" ' +
      'OR (nfce_status = "ERRO" AND (nfce_lock IS NULL OR nfce_lock <= DATE_SUB(NOW(), INTERVAL '
      + IntToStr(IntervaloReenvioMinutos) + ' MINUTE)))) ' +
      'AND (codigo > 0) AND data_pedido >= DATE_FORMAT(CURDATE(), "%Y-%m-01") '
      + 'ORDER BY codigo ' + 'LIMIT ' + IntToStr(Limit);
    conexao.ExecuteSQL;

    // 2) retorna o que foi travado agora
    conexao.SQL.Text := 'SELECT * FROM pedido ' +
      'WHERE nfce_status = "PROCESSANDO" ' +
      'AND nfce_lock >= DATE_SUB(NOW(), INTERVAL 1 MINUTE) ' +
      'AND data_pedido >= DATE_FORMAT(CURDATE(), "%Y-%m-01") ';
    conexao.SQL.Add('LIMIT ' + IntToStr(Limit));

    Res.Send<TJSONArray>(conexao.ConsultaSQL);

  finally
    conexao.Free;
  end;

end;

procedure DoEnviarEmailNFCe(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  Chave: String;
  Email: String;
  Body: TJSONObject;
begin
try
  Chave := Req.Params['chave'];
except
end;
try
  Email := Req.Params['email'];
except

end;

  if (Chave = '') or (Email = '') then
  begin
    Body := TJSONObject.ParseJSONValue(Req.Body) as TJSONObject;
    try
      if Assigned(Body) then
      begin
        if Assigned(Body.GetValue('chave')) then
          Chave := Body.GetValue('chave').Value;
        if Assigned(Body.GetValue('email')) then
          Email := Body.GetValue('email').Value;
      end;
    finally
      Body.Free;
    end;
  end;

  EnviarEmailNFCe(Chave, Email);
  EmailFiscal(Chave, Email);
  Res.Send('E-mail da NFC-e enviado com sucesso.');
end;
procedure DoGetErrosFiscais(Req: THorseRequest; Res: THorseResponse;
  Next: TProc);
var
  conexao: TConexao;
  DataInicio, DataFim: String;
begin
  conexao := TConexao.Create('nfce');
  try
    DataInicio := Req.Params['data_inicio'];
    DataFim := Req.Params['data_fim'];

    conexao.SQL.Add('SELECT ');
    conexao.SQL.Add('ef.id,');
    conexao.SQL.Add('ef.origem,');
    conexao.SQL.Add('ef.mensagem,');
    conexao.SQL.Add('ef.contador,');
    conexao.SQL.Add('COUNT(efp.pedido_id) AS contador_periodo,');
    conexao.SQL.Add('ef.primeiro_em,');
    conexao.SQL.Add('ef.ultimo_em,');
    conexao.SQL.Add
      ('GROUP_CONCAT(efp.pedido_id ORDER BY efp.pedido_id SEPARATOR '','') AS pedidos');
    conexao.SQL.Add('FROM erro_fiscal ef');
    conexao.SQL.Add
      ('JOIN erro_fiscal_pedido efp ON efp.erro_fiscal_id = ef.id');
    conexao.SQL.Add('WHERE DATE(efp.criado_em) BETWEEN :data_inicio AND :data_fim');
    conexao.SQL.Add('GROUP BY ef.id, ef.origem, ef.mensagem, ef.contador,');
    conexao.SQL.Add('ef.primeiro_em, ef.ultimo_em');
    conexao.SQL.Add('ORDER BY contador_periodo DESC, ef.ultimo_em DESC');
    conexao.Parametros('data_inicio', DataInicio);
    conexao.Parametros('data_fim', DataFim);

    Res.Send<TJSONArray>(conexao.ConsultaSQL);
  finally
    conexao.Free;
  end;
end;
procedure Registry;
begin
  THorse.Get('/nfce/pedido/outras/:codigo', DoGetPedidoOutros);
  THorse.Get('/nfce/pedido/produtos/:codigo', DoGetProdutosPedido);
  THorse.Get('/nfce/pedido/pagamento/:codigo', DoGetPedidoPagamento);
  THorse.Get('/nfce/numero', DoGetNumeroNota);
  THorse.Get('/nfce/lote', DoGetNumeroLote);
  THorse.Get('/nfce/emissao', DOGetNFCeEmissao);
  THorse.Post('/nfce/emissao/:codigo/:numero/:chave/:protocolo/:ambiente',
    DoPostEmissaoNFCe);

  THorse.Get('/nfce/contabilidade', DoGetNFceContabilidade);
  THorse.Post('/nfce/contabilidade/:status/:msg', DoPostNFceContabilidade);
  THorse.Get('/nfce/contabilidade/notas/:mes', DoGetNotas);

  THorse.Post('/nfce/code/motivo', DoPostCodeMotivo);
  THorse.Post('/nfce/code', DoPostCode);
  THorse.Get('/nfce/code', DoGetCode);

  THorse.Get('/nfce/notas/sinc', DoGetNotasPendentesSinc);
  THorse.Post('/nfce/nota/sinc/:chave', DoPostNotaSinc);

  THorse.Post('/dfe/sincronizar/:cnpj', DoPostDFESincronizar);
  THorse.Post('/dfe/consultar', DoConsultarDFe);
  THorse.Post('/dfe/consultar/:cnpj', DoConsultarDFe);
  THorse.Get('/dfe/consultar', DoConsultarDFe);
  THorse.Get('/dfe/consultar/:cnpj', DoConsultarDFe);
  THorse.Get('/dfe/listar/:data_inicio/:data_fim', DoListarNotasDFeManifestacao);
  THorse.Get('/dfe/xml/:chave', DoConsultarXMLDFePorChave);
  THorse.Post('/dfe/xml/:chave', DoConsultarXMLDFePorChave);
  THorse.Post('/dfe/importar/manual', DoPostSimularImportacaoDFeArquivo);
  THorse.Post('/dfe/evento', DoEventoDFe);
  THorse.Post('/dfe/manifestar/:chave/:tipo', DoManifestarDFe);
  THorse.Get('/nfe/status-servico', DoConsultarStatusServicoNFe);
  THorse.Post('/nfe/status-servico', DoConsultarStatusServicoNFe);
  THorse.Get('/nfe/status-servico/cache', DoGetStatusServicoNFeGravado);
  THorse.Get('/dfe/ultimo/:cnpj', DoGetUltimoNSU);
  THorse.Get('/dfe/notas/:data_inicio/:data_fim', DoGetNotasDFe);
  THorse.Get('/notas-fiscais/:data_inicio/:data_fim', DoGetNotasFiscais);
  THorse.Get('/dfe/verifica/:ambiente', DoVerificaConsulta);

  THorse.Get('/nfce/fila', DoGetNFCeFila);
  THorse.Get('/nfce/erros/:data_inicio/:data_fim', DoGetErrosFiscais);
  THorse.Get('/nfce/email/:chave/:email', DoEnviarEmailNFCe);
  THorse.Post('/nfce/email/:chave/:email', DoEnviarEmailNFCe);
  THorse.Post('/nfce/email', DoEnviarEmailNFCe);

end;

end.
