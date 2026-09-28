unit uControllCaches;

interface

uses
  JOSE.Types.JSON, uCacheControl, IOUtils, uControlerProduto,
  FireDAC.Comp.Client, Dataset.Serialize, System.Variants;

function GetProdutoAdiciona(chave: String): TJsonArray;
function GetProdutoSabores(chave: String): TJsonArray;
function GetCategoria(chave: String): TJsonArray;
function GetAllCategoria(chave: String): TJsonArray;
function GetFichaProduto(chave: String): TJsonArray;
function GetFichaSabor(chave: String): TJsonArray;
function GetProdutoCategoria(chave,hash: String): TJsonArray;
function GetProdutoPesquisa(chave: String): TJsonArray;
function GetParametros: TJsonArray;
procedure InicializarParametrosCache;
procedure LimparParametrosCacheMemoria;
function GetFlavor(chave: String): TJsonArray;

procedure LimpaCacheGeral;
procedure BuscaCacheGeral;
procedure GetAllProduto(Codigo: Integer);
procedure AtualizaParametro;
function GetProdutoVenda(Body, Codigo: String): TJSONObject;
function BuscarProdutoPorChave(Tipo: string; chave: Integer): TJSONValue;
function MontarArvoreMenu(const Itens: TFDMemTable; PaiId: Variant): TJsonArray;
function JSONIntOrNull(JSON: TJSONObject; const Key: string): Variant;
function SnakeToCamel(const Texto: string): string;

implementation

uses
  conexao, uSQL, System.SysUtils, System.Classes, Vcl.Dialogs,
  System.Diagnostics, System.SyncObjs, System.DateUtils;

var
  ParametrosCacheLock: TCriticalSection;
  ParametrosCacheInicializado: Boolean = False;
  ParametrosCacheJSON: string = '';
  ParametrosCacheExpiraEm: TDateTime = 0;

procedure LimparParametrosCacheMemoria;
begin
  ParametrosCacheLock.Acquire;
  try
    ParametrosCacheJSON := '';
    ParametrosCacheExpiraEm := 0;
  finally
    ParametrosCacheLock.Release;
  end;
end;

procedure GarantirTabelaConfiguracoes;
var
  conexao: TConexao;
  Qry: TFDQuery;
  Migrador: TSQL;
  Existe: Boolean;
begin
  conexao := nil;
  Qry := nil;
  conexao := TConexao.Create('GarantirTabelaConfiguracoes');
  Qry := conexao.CriaQRY;
  try
    Qry.SQL.Text := 'SELECT COUNT(*) AS total FROM information_schema.tables ' +
      'WHERE table_schema = DATABASE() AND table_name = ''configuracoes''';
    Qry.Open;
    Existe := Qry.FieldByName('total').AsInteger > 0;
    if not Existe then
    begin
      Qry.Close;
      Qry.SQL.Clear;
      Qry.SQL.Add('CREATE TABLE configuracoes (');
      Qry.SQL.Add('  chave VARCHAR(100) PRIMARY KEY,');
      Qry.SQL.Add('  valor TEXT');
      Qry.SQL.Add(') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');
      Qry.ExecSQL;
      Migrador := TSQL.Create;
      try
        Migrador.MigrarDadosWhatsappParaConfig;
      finally
        Migrador.Free;
      end;
    end;
  finally
    if Assigned(Qry) then
      Qry.Free;
    if Assigned(conexao) then
      conexao.Free;
  end;
end;

procedure InicializarParametrosCache;
begin
  ParametrosCacheLock.Acquire;
  try
    if ParametrosCacheInicializado then
      Exit;

    GarantirTabelaConfiguracoes;
    ParametrosCacheInicializado := True;
  finally
    ParametrosCacheLock.Release;
  end;
end;

function GetFlavor(chave: String): TJsonArray;
var
  conexao: TConexao;
  ArrayJson: TJsonArray;
  ObjetoJson: TJSONObject;
  ArrayProdutos: TJsonArray;
  ObjetoProduto: TJSONObject;
  Dados: TFDMemTable;
  DadosProduto: TFDMemTable;
  DadosAux: TFDMemTable;
  DadosSabores: TFDMemTable;
  valor: Real;
  Codigo: Integer;
  CodigoProdutos: String;
begin

  Result := BuscaCache('GetFlavor', chave);
  if Result.Count = 0 then
  begin
    conexao := TConexao.Create('v2');
    try
      DadosProduto := TFDMemTable.Create(nil);
      Dados := TFDMemTable.Create(nil);
      DadosAux := TFDMemTable.Create(nil);
      ArrayJson := TJsonArray.Create;
      DadosSabores := TFDMemTable.Create(nil);

      conexao.SQL.Add('select * from produto');
      conexao.SQL.Add
        ('join tipo_produto on tipo_produto.codigo = produto.codigo_grupo and tipo_produto.pizza = 1');
      conexao.SQL.Add
        ('where produto.codigo_grupo = :grupo and deletado <> 1 order by produto.position');
      conexao.Parametros('grupo', chave);
      DadosProduto.LoadFromJSON(conexao.ConsultaSQL);

      while not DadosProduto.Eof do
      begin
        if CodigoProdutos = '' then
        begin
          CodigoProdutos := DadosProduto.FieldByName('codigo').AsString;
        end
        else
        begin
          CodigoProdutos := CodigoProdutos + ',' + DadosProduto.FieldByName
            ('codigo').AsString;
        end;

        DadosProduto.Next;
      end;

      if CodigoProdutos <> '' then
      begin
        // conexao.SQL.Add('SELECT distinct sabores_completo.nome, ativo, descricao,url, (SELECT upper(nome) FROM tipo_sabor where id = id_tipo_sabor) as id_tipo_sabor FROM sabores_completo where id_produto in ('+ CodigoProdutos + ') order by id_tipo_sabor');
        conexao.SQL.Add('SELECT ');
        conexao.SQL.Add('  (s.nome) AS nome,');
        conexao.SQL.Add('  MAX(s.ativo) AS ativo,');
        conexao.SQL.Add('  MAX(s.descricao) AS descricao,');
        conexao.SQL.Add('  MAX(s.url) AS url,');
        conexao.SQL.Add('  UPPER(MAX(ts.nome)) AS tipo_sabor,');
        conexao.SQL.Add('  MAX(s.id_tipo_sabor) AS id_tipo_sabor,');
        conexao.SQL.Add('  MAX(s.ultima_compra) AS ultima_compra');
        conexao.SQL.Add('FROM sabores_completo s');
        conexao.SQL.Add('LEFT JOIN tipo_sabor ts ON ts.id = s.id_tipo_sabor');
        conexao.SQL.Add('WHERE s.id_produto IN (' + CodigoProdutos + ')');
        conexao.SQL.Add('GROUP BY (s.nome)');
        conexao.SQL.Add('ORDER BY tipo_sabor;');
        Dados.LoadFromJSON(conexao.ConsultaSQL);

        DadosProduto.First;
        while not Dados.Eof do
        begin

          ObjetoJson := TJSONObject.Create;
          ObjetoJson.AddPair('flavor', Dados.FieldByName('nome').AsString);
          ObjetoJson.AddPair('url', Dados.FieldByName('url').AsString);
          ObjetoJson.AddPair('description', Dados.FieldByName('descricao')
            .AsString);
          ObjetoJson.AddPair('status', Dados.FieldByName('ativo').AsInteger);
          ObjetoJson.AddPair('ultimaCompra',
            FormatDateTime('yyyy-mm-dd', Dados.FieldByName('ultima_compra')
            .AsDateTime));
          ObjetoJson.AddPair('type', Dados.FieldByName('id_tipo_sabor')
            .AsString);
          ArrayProdutos := TJsonArray.Create;
          DadosProduto.First;
          while not DadosProduto.Eof do
          begin

            DadosSabores.Close;
            conexao.SQL.Add
              ('select * from sabores_completo where id_produto = :produto and nome = :sabor order by vl_venda desc limit 1');
            conexao.Parametros('produto', DadosProduto.FieldByName('codigo')
              .AsInteger);
            conexao.Parametros('sabor', Dados.FieldByName('nome').AsString);
            DadosSabores.LoadFromJSON(conexao.ConsultaSQL);

            if DadosSabores.RecordCount = 0 then
            begin
              valor := 0;
            end
            else
            begin
              valor := DadosSabores.FieldByName('vl_venda').AsFloat;
            end;

            ObjetoProduto := TJSONObject.Create;

            ObjetoProduto.AddPair('id', DadosProduto.FieldByName('codigo')
              .AsInteger);
            ObjetoProduto.AddPair('name',
              DadosProduto.FieldByName('nome_produto').AsString);
            ObjetoProduto.AddPair('value', valor);

            ArrayProdutos.Add(ObjetoProduto);

            DadosProduto.Next;
          end;
          ObjetoJson.AddPair('product', ArrayProdutos);
          ArrayJson.Add(ObjetoJson);
          Dados.Next;
        end;
      end;
      Result := ArrayJson;
      Dados.Free;
      DadosAux.Free;
      DadosProduto.Free;
      DadosSabores.Free;
    except
      on e: exception do
      begin
        ArrayJson := TJsonArray.Create;
        Result := ArrayJson;

      end;
    end;
    conexao.Free;
    GravaCache('GetFlavor', chave, Result.ToString);
  end;

end;

function GetProdutoVenda(Body, Codigo: String): TJSONObject;
var
  conexao: TConexao;
  JSONObject: TJSONObject;

  QUANTIDADE: Real;
  JsonBody: TJSONObject;
  Data: String;
  Custo: Real;
  Venda: Real;
  CMV: Real;
  ReceitaTotal: Real;
  CMVPercentual: Real;

  URL: String;
begin
  URL := Codigo;
  try
    JsonBody := TJSONObject.ParseJSONValue(Body) as TJSONObject;
    if Assigned(JsonBody) then
    begin
      URL := Codigo + JsonBody.GetValue<String>('inicial') +
        JsonBody.GetValue<String>('final');
    end;
  except

  end;

  Result := BuscaCacheObject('GetProdutoVenda', URL);

  if Result.Count = 0 then
  begin

    conexao := TConexao.Create('CMV');
    JSONObject := TJSONObject.Create;
    conexao.SQL.Add
      ('select sum(pp.quantidade) as total, 0 as zero from pedido as p');
    conexao.SQL.Add
      ('join pedido_produtos as pp on pp.codigo_pedido = p.codigo');
    conexao.SQL.Add('where p.status > 0 and pp.codigo_produto = :codigo');
    conexao.Parametros('codigo', Codigo);
    try

      JsonBody := TJSONObject.ParseJSONValue(Body) as TJSONObject;
      if Assigned(JsonBody) then
      begin
        Data := JsonBody.GetValue<String>('inicial');
        conexao.SQL.Add('and p.data_pedido between :ini and :fim');
        conexao.Parametros('ini', JsonBody.GetValue<String>('inicial'));
        conexao.Parametros('fim', JsonBody.GetValue<String>('final'));

      end;
    except

    end;

    try
      QUANTIDADE := conexao.FieldByName('total');
    except
      QUANTIDADE := 1;
    end;

    JSONObject.AddPair('quantidade', QUANTIDADE);
    if QUANTIDADE = 0 then
    begin
      QUANTIDADE := 1;
    end;

    conexao.SQL.Add
      ('select custo_indiretos  as custo, 0 as zero from cmv where codigo_produto = :codigo order by id desc limit 1 ');
    conexao.Parametros('codigo', Codigo);
    try
      Custo := conexao.FieldByName('custo');
    except
      Custo := 0;
    end;

    conexao.SQL.Add
      ('  select valor_venda as venda, 0 as zero from produto where codigo = :codigo');
    conexao.Parametros('codigo', Codigo);
    try
      Venda := conexao.FieldByName('venda');
    except
      Venda := 0;
    end;

    CMV := Custo * QUANTIDADE;
    ReceitaTotal := Venda * QUANTIDADE;
    CMVPercentual := (CMV / ReceitaTotal) * 100;
    JSONObject.AddPair('cmv', CMVPercentual);

    Result := JSONObject;
    GravaCache('GetProdutoVenda', URL, Result.ToString);
    // Res.Send<TJSONObject>(JSONObject);
    conexao.Free;
  end;

end;

function GetParametros: TJsonArray;
var
  conexao: TConexao;
  ArrayParametro: TJsonArray;
  Objeto: TJSONObject;
  Erro: Boolean;
  Qry: TFDQuery;
  SWStep: TStopwatch;
  SWItem: TStopwatch;
  Serialized: string;

  procedure MarkStep(const StepName: string);
  begin
    SWStep.Stop;
    SWStep := TStopwatch.StartNew;
  end;

  function CloneCachedArray(const JSONText: string): TJsonArray;
  begin
    Result := TJSONObject.ParseJSONValue(JSONText) as TJsonArray;
    if Result = nil then
      Result := TJsonArray.Create;
  end;
begin
  SWStep := TStopwatch.StartNew;
  InicializarParametrosCache;
  MarkStep('init_check');

  ParametrosCacheLock.Acquire;
  try
    if (ParametrosCacheJSON <> '') and (ParametrosCacheExpiraEm > Now) then
      Serialized := ParametrosCacheJSON
    else
      Serialized := '';
  finally
    ParametrosCacheLock.Release;
  end;
  MarkStep('memory_cache_lookup');

  if Serialized <> '' then
  begin
    Result := CloneCachedArray(Serialized);
    MarkStep('memory_cache_parse');
    Exit;
  end;

  Result := BuscaCache('DoGetParametros', 'cache');
  MarkStep('cache_lookup');
  if Result.Count > 0 then
  begin
    Serialized := Result.ToString;
    ParametrosCacheLock.Acquire;
    try
      ParametrosCacheJSON := Serialized;
      ParametrosCacheExpiraEm := IncSecond(Now, 60);
    finally
      ParametrosCacheLock.Release;
    end;
    MarkStep('memory_cache_store_from_cache');
    Exit;
  end;

  conexao := TConexao.Create('Util');
  try
    MarkStep('connection_create');
    Qry := conexao.CriaQRY;
    try
      MarkStep('query_create');
      Qry.SQL.Add('select chave, valor from configuracoes');
      Qry.Open;
      SWStep := TStopwatch.StartNew;
      Objeto := TJSONObject.Create;
      ArrayParametro := TJsonArray.Create;
      if Qry.RecordCount > 0 then
      begin
        while not Qry.Eof do
        begin
          SWItem := TStopwatch.StartNew;
          try
            Erro := False;
            Objeto.AddPair(SnakeToCamel(Qry.FieldByName('chave').AsString),
              Qry.FieldByName('valor').AsInteger)
          except
            Erro := True;
          end;
          if Erro then
          begin
            try
              Erro := False;
              Objeto.AddPair(SnakeToCamel(Qry.FieldByName('chave').AsString),
                Qry.FieldByName('valor').AsFloat)
            except
              Erro := True;
            end;
          end;
          if Erro then
          begin
            try
              Erro := False;
              Objeto.AddPair(SnakeToCamel(Qry.FieldByName('chave').AsString),
                Qry.FieldByName('valor').AsWideString)
            except
              Erro := True;
            end;
          end;
          SWItem.Stop;


          Qry.Next;
        end;
      end;
      MarkStep('parameter_loop');
      ArrayParametro.Add(Objeto);
      Result := ArrayParametro;
      MarkStep('json_build');
      Serialized := Result.ToString;
      ParametrosCacheLock.Acquire;
      try
        ParametrosCacheJSON := Serialized;
        ParametrosCacheExpiraEm := IncSecond(Now, 60);
      finally
        ParametrosCacheLock.Release;
      end;
      MarkStep('memory_cache_store');
      GravaCache('DoGetParametros', 'cache', Serialized);
      MarkStep('cache_write');
    finally
      Qry.Free;
    end;
  finally
    conexao.Free;
    SWStep.Stop;
  end;
end;
function GetProdutoAdiciona(chave: String): TJsonArray;
var
  conexao: TConexao;
begin

  Result := BuscaCache('DoGetProdutoAdiciona', chave);
  if Result.Count = 0 then
  begin
    conexao := TConexao.Create('Util');
    conexao.SQL.Add
      ('select paps.id as codigo, pap.descricao as categoria, paps.nome, paps.valor, p.observacao, qtd_minima as min, qtd_maxima as max from produto as p');
    // conexao.SQL.Add('inner join pro_adi_personalizado as pap on pap.id_produto = p.codigo');
    conexao.SQL.Add
      ('inner join pro_adi_personalizado as pap on pap.id_produto = p.codigo or pap.categoria = p.codigo_grupo');
    conexao.SQL.Add
      ('inner join pro_adi_personalizado_sabores as paps on paps.id_pro_adi_personalizado = pap.id and paps.ativo = 1');
    conexao.SQL.Add
      ('where p.codigo = :codigo order by pap.categoria desc, paps.id_pro_adi_personalizado');
    conexao.Parametros('codigo', chave);
    Result := conexao.ConsultaSQL;
    GravaCache('DoGetProdutoAdiciona', chave, Result.ToString);
    conexao.Free;
  end;

end;

function GetProdutoSabores(chave: String): TJsonArray;
var
  conexao: TConexao;
begin

  Result := BuscaCache('DoGetProdutoSabores', chave);
  if Result.Count = 0 then
  begin
    conexao := TConexao.Create('Util');
    conexao.SQL.Add
      ('SELECT pp.quantidade_sabores, sc.nome, sc.vl_venda, sc.id, (SELECT tipo_preco_pizza FROM dados_whatsapp limit 1) as tipo_preco, (select nome from tipo_sabor where id = id_tipo_sabor) as tipo FROM produto_pizza as pp');
    conexao.SQL.Add
      ('join sabores_completo as sc on sc.id_produto = pp.codigo_produto');
    conexao.SQL.Add('where sc.id_produto = :codigo');
    conexao.SQL.Add('order by sc.id_tipo_sabor, sc.nome');
    conexao.Parametros('codigo', chave);
    Result := conexao.ConsultaSQL;
    GravaCache('DoGetProdutoSabores', chave, Result.ToString);
    conexao.Free;
  end;

end;

function GetCategoria(chave: String): TJsonArray;
var
  conexao: TConexao;
begin

  Result := BuscaCache('GetCategoria', chave);

  if Result.Count = 0 then
  begin
    conexao := TConexao.Create('Util');
    conexao.SQL.Add
      ('SELECT  tp.*, (select count(*) from produto where codigo_grupo = tp.codigo and deletado = 0) as quant FROM tipo_produto as tp');
    conexao.SQL.Add('ORDER BY tp.ordem;');
    Result := conexao.ConsultaSQL;
    GravaCache('GetCategoria', chave, Result.ToString);
    conexao.Free;
  end;

end;

function GetAllCategoria(chave: String): TJsonArray;
var
  conexao: TConexao;
begin
  Result := BuscaCache('DoGetAllCategoria', chave);
  if Result.Count = 0 then
  begin
    conexao := TConexao.Create('Util');
    conexao.SQL.Add('SELECT DISTINCT tp.* FROM tipo_produto as tp');
    conexao.SQL.Add('HAVING (SELECT COUNT(*) FROM produto WHERE produto.codigo_grupo = tp.codigo and produto.ativo = 1) > 0');
    conexao.SQL.Add('ORDER BY tp.ordem;');
    Result := conexao.ConsultaSQL;
    GravaCache('DoGetAllCategoria', chave, Result.ToString);
    conexao.Free;
  end;
end;

function GetFichaProduto(chave: String): TJsonArray;
var
  conexao: TConexao;
begin
  Result := BuscaCache('GetFichaProduto', chave);

  if Result.Count = 0 then
  begin
    conexao := TConexao.Create('Util');
    conexao.SQL.Add
      ('select produto_ingredientes.*, ingredientes.descricao, ingredientes.unidade, ingredientes.custo from produto_ingredientes');
    conexao.SQL.Add
      ('join ingredientes on ingredientes.id = produto_ingredientes.id_ingredientes');
    conexao.SQL.Add('where produto_ingredientes.id_produto = :produto');
    conexao.Parametros('produto', chave);
    Result := conexao.ConsultaSQL;
    GravaCache('GetFichaProduto', chave, Result.ToString);
    conexao.Free;
  end;
end;

function GetProdutoCategoria(chave,hash: String): TJsonArray;
var
  conexao: TConexao;
  SQL: String;
begin
  Result := BuscaCache('GetProdutoCategoria', chave);

  if Result.Count = 0 then
  begin
    if chave = '0' then
    begin
      SQL := 'select produto.* from produto ';
      SQL := SQL +
        ' join tipo_produto on tipo_produto.codigo = produto.codigo_grupo ';
      SQL := SQL + ' where produto.deletado <> 1 ';
      SQL := SQL + ' order by codigo_grupo,position';
    end
    else
    begin
      SQL := 'select produto.* from produto ';
      SQL := SQL +
        ' join tipo_produto on tipo_produto.codigo = produto.codigo_grupo ';
      SQL := SQL + ' where produto.deletado <> 1 and codigo_grupo = ' + chave;
      SQL := SQL + ' order by codigo_grupo,position';
    end;
    Result := ObjetoProduto(SQL,hash);
    GravaCache('GetProdutoCategoria', chave, Result.ToString);
  end;
end;

function GetProdutoPesquisa(chave: String): TJsonArray;
var
  conexao: TConexao;
  SQL: String;
begin
  Result := BuscaCache('GetProdutoPesquisa', chave);
  if (length(chave) < 3) then
  begin
    Result := TJsonArray.Create;
    exit;
  end;
  if Result.Count = 0 then
  begin
    SQL := ' SELECT * FROM produto WHERE ativo = 1 and deletado = 0 and upper(nome_produto) COLLATE utf8_general_ci LIKE "%'+ UpperCase(chave) + '%" ORDER BY position LIMIT 10';
    Result := ObjetoProduto(SQL,chave);
    GravaCache('GetProdutoCategoria', chave, Result.ToString);
  end;

end;

procedure LimpaCacheGeral;
begin
  ClearAll;
end;

procedure BuscaCacheGeral;
begin
  TThread.CreateAnonymousThread(
    procedure
    var
      Categorias: TJsonArray;
      I: Integer;
      Categoria: TJSONObject;
      Codigo: TJSONValue;

      Produtos: TJsonArray;
      K: Integer;
      Produto: TJSONObject;
      CodigoProduto: TJSONValue;
    begin
      try
        LimpaCacheGeral;
        Categorias := GetCategoria('all');
        GetAllCategoria('all');

        // Verifica se o array de categorias ? v?lido
        if Assigned(Categorias) then
        begin
          for I := 0 to Categorias.Count - 1 do
          begin
            // Converte cada item do array para um objeto JSON
            Categoria := Categorias.Items[I] as TJSONObject;

            // Pega o valor do campo 'codigo'
            Codigo := Categoria.GetValue('codigo');
            if Assigned(Codigo) then
            begin
              // Mostra o valor do campo 'codigo'
              Produtos := GetProdutoCategoria(Codigo.Value,'');

              if Assigned(Produtos) then
              begin
                for K := 0 to Produtos.Count - 1 do
                begin
                  Produto := Produtos.Items[K] as TJSONObject;
                  if Assigned(Produto) then
                  begin
                    CodigoProduto := Produto.GetValue('id');
                    GetAllProduto(StrToInt(CodigoProduto.Value));
                  end;
                end;
              end;
            end;
          end;
        end;
      except
        on e: exception do
        begin

        end;
      end;
    end).Start;
end;

procedure GetAllProduto(Codigo: Integer);
var
  conexao: TConexao;
  CodigoGrupo: Integer;
begin
  conexao := TConexao.Create('GetAllProduto');
  conexao.SQL.Add('select * from produto where codigo = :codigo');
  conexao.Parametros('codigo', Codigo);
  CodigoGrupo := conexao.FieldByName('codigo_grupo');

  LimpaCache('DoGetProdutoAdiciona', Codigo.ToString);
  LimpaCache('DoGetProdutoSabores', Codigo.ToString);
  LimpaCache('GetFichaProduto', Codigo.ToString);
  LimpaCache('GetProdutoCategoria', CodigoGrupo.ToString);
  // //////showmessage1(CodigoGrupo.ToString);

  GetProdutoCategoria(CodigoGrupo.ToString,'');
  GetProdutoAdiciona(Codigo.ToString);
  GetProdutoSabores(Codigo.ToString);
  GetFichaProduto(Codigo.ToString);
  conexao.Free;
end;

procedure AtualizaParametro;
begin
  LimparParametrosCacheMemoria;
  LimpaCache('DoGetParametros', 'cache');
  GetParametros;

end;

function GetFichaSabor(chave: String): TJsonArray;
var
  conexao: TConexao;
begin
  Result := BuscaCache('GetFichaSabor', chave);

  if Result.Count = 0 then
  begin
    conexao := TConexao.Create('Util');
    try
      conexao.SQL.Add('SELECT sci.*, ing.descricao, ing.unidade, ing.custo ' +
        'FROM sabores_completo_ingrediente sci ' +
        'JOIN ingredientes ing ON ing.id = sci.id_ingrediente ' +
        'WHERE sci.id_sabor_completo = :id_sabor_completo');
      conexao.Parametros('id_sabor_completo', chave);
      Result := conexao.ConsultaSQL;
      GravaCache('GetFichaSabor', chave, Result.ToString);
    finally
      conexao.Free;
    end;
  end;
end;

function BuscarProdutoPorChave(Tipo: string; chave: Integer): TJSONValue;
var
  SQL: string;
begin
  if Tipo = 'CATEGORIA' then
  begin
    SQL := 'select produto.* from produto ';
    SQL := SQL +
      ' join tipo_produto on tipo_produto.codigo = produto.codigo_grupo ';
    SQL := SQL + ' where produto.deletado <> 1 and codigo_grupo = ' +
      chave.ToString;
    SQL := SQL + ' order by codigo_grupo, position';
  end
  else
  begin
    SQL := 'select * from produto ';
    SQL := SQL + ' where produto.deletado <> 1 and codigo = ' + chave.ToString;
    SQL := SQL + ' order by codigo_grupo, position';
  end;

  Result := ObjetoProduto(SQL,Tipo); // ?? j? retorna JSON
end;

// function MontarArvoreMenu(const Itens: TFDMemTable; PaiId: Variant): TJsonArray;
// var
// Arr: TJsonArray;
// Obj: TJSONObject;
// begin
// Arr := TJsonArray.Create;
//
// Itens.First;
// while not Itens.Eof do
// begin
// if VarSameValue(Itens.FieldByName('pai_id').Value, 0) then
// begin
// Obj := TJSONObject.Create;
// Obj.AddPair('id', Itens.FieldByName('id').AsInteger);
// Obj.AddPair('nome', Itens.FieldByName('nome').AsString);
//
// // Produto direto
// if not Itens.FieldByName('produto_id').IsNull then
// begin
// Obj.AddPair('produto', BuscarProdutoPorChave('PRODUTO',
// Itens.FieldByName('produto_id').AsInteger));
// end
// // Categoria
// else if not Itens.FieldByName('categoria_id').IsNull then
// begin
// Obj.AddPair('produtos', BuscarProdutoPorChave('CATEGORIA',
// Itens.FieldByName('categoria_id').AsInteger));
// end
// // Agrupador
// else
// begin
// Obj.AddPair('children', MontarArvoreMenu(Itens, Itens.FieldByName('id')
// .AsInteger));
// end;
//
// Arr.AddElement(Obj);
// end;
//
// Itens.Next;
// end;
//
// Result := Arr;
// end;

function MontarArvoreMenu(const Itens: TFDMemTable; PaiId: Variant): TJsonArray;
var
  Arr: TJsonArray;
  Obj: TJSONObject;
  EhRaiz: Boolean;
begin
  Arr := TJsonArray.Create;
  EhRaiz := VarIsNull(PaiId);

  Itens.First;
  while not Itens.Eof do
  begin
    // raiz
    if EhRaiz and (Itens.FieldByName('pai_id').AsFloat = 0) then
    begin
      Obj := TJSONObject.Create;
    end
    // filhos
    else if (not EhRaiz) and (not(Itens.FieldByName('pai_id').AsFloat = 0)) and
      (Itens.FieldByName('pai_id').AsInteger = PaiId) then
    begin
      Obj := TJSONObject.Create;
    end
    else
    begin
      Itens.Next;
      Continue;
    end;

    // dados comuns
    Obj.AddPair('id', Itens.FieldByName('id').AsInteger);
    Obj.AddPair('nome', Itens.FieldByName('nome').AsString);

    // conte?do
    if Itens.FieldByName('produto_id').AsFloat > 0 then
    begin
      Obj.AddPair('produto', BuscarProdutoPorChave('PRODUTO',
        Itens.FieldByName('produto_id').AsInteger));
    end
    else if Itens.FieldByName('categoria_id').AsFloat > 0 then
    begin
      Obj.AddPair('produtos', BuscarProdutoPorChave('CATEGORIA',
        Itens.FieldByName('categoria_id').AsInteger));
    end;

    // filhos (sempre!)
    Obj.AddPair('children', MontarArvoreMenu(Itens, Itens.FieldByName('id')
      .AsInteger));

    Arr.AddElement(Obj);
    Itens.Next;
  end;

  Result := Arr;
end;

function JSONIntOrNull(JSON: TJSONObject; const Key: string): Variant;
var
  V: TJSONValue;
begin
  Result := Null;

  if not JSON.TryGetValue(Key, V) then
    exit;

  if V is TJSONNull then
    exit;

  Result := V.AsType<Integer>;
end;

function SnakeToCamel(const Texto: string): string;
var
  i: Integer;
  UpperNext: Boolean;
begin
  Result := '';
  UpperNext := False;

  for i := 1 to Length(Texto) do
  begin
    if Texto[i] = '_' then
    begin
      UpperNext := True;
      Continue;
    end;

    if UpperNext then
    begin
      Result := Result + UpperCase(Texto[i]);
      UpperNext := False;
    end
    else
    begin
      Result := Result + LowerCase(Texto[i]);
    end;
  end;
end;

initialization
  ParametrosCacheLock := TCriticalSection.Create;

finalization
  ParametrosCacheLock.Free;

end.
