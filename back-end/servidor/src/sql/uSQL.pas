unit uSQL;

interface

uses
  IdComponent, IdTCPConnection, IdTCPClient, IdExplicitTLSClientServerBase,
  IdFTP, System.Zip, ShellAPI, Registry, System.Classes, FMX.StdCtrls,
  Vcl.StdCtrls, FireDAC.Comp.Client, DataSet.Serialize;

procedure ConfigurarParametrosAtualizacaoPadrao;

type
  TCallback = procedure of object;

  TSQL = class
  private
    { O Controle de atualiza��o do banco vai ser por enquanto com base na vers�o do executavel }
    Function VersaoExe: String;
    procedure AtualizaCodigoUltimaVersao;
    function ExecultaSQL(SQL: String): Boolean;
    function VerificaSQL: Boolean;
    procedure AtualizaBanco;
    procedure Banco(Versao: Integer);
    procedure CarregarClassTribSeed;
    procedure IniciaAtualizacao;
    function UltimoCodigo(tabela, campo: String): string;

    function MaiorValorDaLista(const Lista: string): Integer;
    function ValoresSemMaior(const Lista: string): string;
    procedure CriarPrimeiraParticaoPedidoAll;
    procedure iniciaSerieNFCE;
    function FromDays(Days: Integer): TDate;

  var

    CodigoSQL: Integer;
    UltimoSQL: Integer; // Inicial 1
    UltimoSQLBanco: Integer;
    ListaSQL: TStringList;
  public
    constructor Create;
    procedure VerificaAtualizacao;
    procedure AtualizarBanco;
    procedure AtualizarBancoNovo;
    procedure LimpaClientesDuplicado;
    procedure ProcessaHistoricoCliente(DataBase: TDate);
    procedure MigrarDadosWhatsappParaConfig;

  var
    SeTiverAtualizacao: TCallback;
    seNaoTiverAtualizacao: TCallback;
    IniciarAtualizacao: TCallback;
    AposConcluirAtualizacao: TCallback;
    AtualizaEstoque: TCallback;
    LabelInfo: TLabel;
    MemoLog: TMemo;
    StatusAtualizacao: Integer;

  end;

implementation

{ TSQL }

uses conexao, System.SysUtils;

procedure ConfigurarParametrosAtualizacaoPadrao;
const
  ATUALIZACAO_EXECUTAVEIS_PADRAO =
    'atualizador.exe;GooPedir.exe;ServicosGoopedir.exe;SiteGooPedir.exe;' +
    'ImpressaoGooPedir.exe;NFCe.exe;WhatsappGoPedir.exe;psGoopedir.exe';
var
  conexao: TConexao;

  procedure InserirParametroPadrao(const Chave, Valor: string);
  begin
    conexao.SQL.Add('INSERT INTO configuracoes (chave, valor)');
    conexao.SQL.Add('VALUES (:chave, :valor)');
    conexao.SQL.Add('ON DUPLICATE KEY UPDATE valor = valor');
    conexao.Parametros('chave', Chave);
    conexao.Parametros('valor', Valor);
    conexao.ExecuteSQL;
  end;

begin
  conexao := TConexao.Create('ConfigurarParametrosAtualizacaoPadrao');
  try
    conexao.ExecuteSQL('CREATE TABLE IF NOT EXISTS configuracoes (' +
      'chave VARCHAR(100) PRIMARY KEY,' + 'valor TEXT' +
      ') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');

    InserirParametroPadrao('atualizacao_ambiente', 'producao');
    InserirParametroPadrao('atualizacao_token', 'IWC8cNw2RrgbL7280RSaTzzoD8LrWS3YjbhT24J8lfT');
    InserirParametroPadrao('atualizacao_url',
      'https://atualizacao.goopedir.com/');
    InserirParametroPadrao('atualizacao_executaveis',
      ATUALIZACAO_EXECUTAVEIS_PADRAO);

{$IFDEF DEBUG}
    conexao.SalvarParametro('atualizacao_ambiente', 'testes');
{$ENDIF}
  finally
    conexao.Free;
  end;
end;

procedure TSQL.AtualizaBanco;
var
  I: Integer;
  Inicio: Integer;
begin
  // frmAtualizandoSQL := TfrmAtualizandoSQL.Create(nil);
  // sleep(1000);
  // frmAtualizandoSQL.Refresh;
  // frmAtualizandoSQL.Repaint;
  // frmAtualizandoSQL.Visible := True;
  // frmAtualizandoSQL.Refresh;
  // frmAtualizandoSQL.Repaint;

  for I := UltimoSQLBanco to UltimoSQL do
  begin
    Banco(I);
  end;

  // frmAtualizandoSQL.Free;
end;

procedure TSQL.AtualizaCodigoUltimaVersao;
var
  Versao: String;
begin
  Versao := VersaoExe;
  Versao := Copy(Versao, 7, 4);
  UltimoSQL := StrToInt(Versao);
end;

procedure TSQL.AtualizarBanco;
Var
  I: Integer;
begin
  // Banco(VersaoExe.ToInteger);

  for I := UltimoSQLBanco to VersaoExe.ToInteger do
  begin
    Banco(I);
  end;

  TThread.CreateAnonymousThread(
    procedure
    begin

      IniciaAtualizacao;
      TThread.Synchronize(TThread.CurrentThread,
        procedure
        begin

          if Assigned(AposConcluirAtualizacao) then
          begin
            AposConcluirAtualizacao;

          end;
          iniciaSerieNFCE;
          StatusAtualizacao := 1;
        end);
    end).Start;

end;

procedure TSQL.AtualizarBancoNovo;
var
  I: Integer;
  VersaoAtual: Integer;
  conexao: TConexao;
begin
  ListaSQL.Clear;
  UltimoSQLBanco := 0;
  VersaoAtual := StrToIntDef(VersaoExe, 0);

  conexao := TConexao.Create('uSQL BancoNovo');
  try
    conexao.ExecuteSQL('CREATE TABLE IF NOT EXISTS configuracoes (' +
      'chave VARCHAR(100) PRIMARY KEY,' + 'valor TEXT' +
      ') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');

    conexao.ExecuteSQL('CREATE TABLE IF NOT EXISTS MEU_SQL (' +
      'IDSQL INTEGER,VERSAOSQL INTEGER, SQLUSADOSQL BLOB, ERROSQL BLOB,' +
      'DATASQL DATE, HORASQL TIME, STATUSSQL VARCHAR(15));');
  finally
    conexao.Free;
  end;

  for I := UltimoSQLBanco to VersaoAtual do
    Banco(I);

  conexao := TConexao.Create('uSQL BancoNovo');
  try
    for I := 0 to ListaSQL.Count - 1 do
      conexao.ExecuteSQL(ListaSQL[I]);

    conexao.ExecuteSQL('CREATE TABLE IF NOT EXISTS configuracoes (' +
      'chave VARCHAR(100) PRIMARY KEY,' + 'valor TEXT' +
      ') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');

    conexao.ExecuteSQL('CREATE TABLE IF NOT EXISTS MEU_SQL (' +
      'IDSQL INTEGER,VERSAOSQL INTEGER, SQLUSADOSQL BLOB, ERROSQL BLOB,' +
      'DATASQL DATE, HORASQL TIME, STATUSSQL VARCHAR(15));');

    conexao.SQL.Add
      ('INSERT INTO MEU_SQL (IDSQL,VERSAOSQL,SQLUSADOSQL,ERROSQL,DATASQL,HORASQL,STATUSSQL) VALUES (:IDSQL,:VERSAOSQL,:SQLUSADOSQL,:ERROSQL,current_date,current_time,:STATUSSQL)');
    conexao.Parametros('IDSQL', conexao.GerarID('MEU_SQL', 'IDSQL'));
    conexao.Parametros('VERSAOSQL', VersaoAtual);
    conexao.Parametros('SQLUSADOSQL',
      'Banco novo atualizado ate a versao local');
    conexao.Parametros('ERROSQL', '');
    conexao.Parametros('STATUSSQL', 'SUCESSO');
    conexao.ExecuteSQL;
  finally
    conexao.Free;
  end;

  StatusAtualizacao := 1;
end;

constructor TSQL.Create;
var
  Versao: String;
begin
  ListaSQL := TStringList.Create;

end;

procedure TSQL.CriarPrimeiraParticaoPedidoAll;
var

  conexao: TConexao;
begin
  conexao := TConexao.Create('CriarPrimeiraParticaoPedidoAll');
  conexao.CriarParticoesHistoricasPedidoAll;
  conexao.ExecuteSQL;
end;

function TSQL.ExecultaSQL(SQL: String): Boolean;
begin
  ListaSQL.Add(SQL);

end;

function TSQL.FromDays(Days: Integer): TDate;
begin
  Result := EncodeDate(0001, 1, 1) + Days - 366;
end;

procedure TSQL.IniciaAtualizacao;
var
  conexao: TConexao;
  I: Integer;
begin
  conexao := TConexao.Create('uSQL');
  MemoLog.Lines.Add
    ('****************************************************************************');
  MemoLog.Lines.Add('');
  MemoLog.Lines.Add('Inicio Atualiza��o');
  MemoLog.Lines.Add('Data/Hora: ' + FormatDateTime('dd/mm/yyyy hh:nn:ss', now));
  MemoLog.Lines.Add('');
  MemoLog.Lines.Add
    ('****************************************************************************');

  for I := 0 to ListaSQL.Count - 1 do
  begin
    MemoLog.Lines.Add('');
    if conexao.ExecutarSQLAtualizacao(ListaSQL[I], VersaoExe) then
    begin
      MemoLog.Lines.Add('Executado com sucesso!');
    end
    else
    begin
      MemoLog.Lines.Add('Erro ao executar!');
    end;
    MemoLog.Lines.Add(FormatDateTime('hh:nn:ss', now));
    MemoLog.Lines.Add
      ('****************************************************************************');
    sleep(200);
  end;
  StatusAtualizacao := 1;

  conexao.Free;
end;

procedure TSQL.iniciaSerieNFCE;
var
  conexao: TConexao;
  Serie: string;
  Numero: Integer;
  qry: TFDQuery;
begin
  conexao := TConexao.Create('iniciaSerieNFCE');
  qry := conexao.CriaQRY;

  Serie := '1';
  Numero := 1;

  qry.SQL.Add('');
  qry.SQL.Add('SELECT');
  qry.SQL.Add('MAX(pedido.nfce_numero) AS numero,');
  qry.SQL.Add('SUBSTRING(MAX(pedido.nfce_chave), 23, 3) AS serie');
  qry.SQL.Add('FROM pedido');
  qry.Open;

  if qry.RecordCount > 0 then
  begin
    try
      Serie := qry.FieldByName('serie').AsString;
      Numero := qry.FieldByName('numero').AsInteger;
    except

    end;
  end;

  conexao.SQL.Add
    ('update dados_whatsapp set nfce_serie = :serie, nfce_numeracao = :numero where nfce_serie = 0');
  conexao.Parametros('serie', Serie);
  conexao.Parametros('numero', Numero);
  conexao.ExecuteSQL;
  qry.Free;
  conexao.Free;

end;

procedure TSQL.LimpaClientesDuplicado;
var
  conexao: TConexao;
  dados: TFDMemTable;
  nomeTabela: TFDMemTable;
  CodigoCliente: Integer;
begin
  conexao := TConexao.Create('LimpaClientesDuplicado');
  nomeTabela := TFDMemTable.Create(nil);
  conexao.SQL.Add
    ('SELECT distinct concat("pedido_",referencia) as tabela, 0 FROM index_pedido');
  nomeTabela.LoadFromJSON(conexao.ConsultaSQL);

  conexao.SQL.Add('SELECT');
  conexao.SQL.Add('    nome_norm,');
  conexao.SQL.Add('    contato_norm,');
  conexao.SQL.Add('    COUNT(*) AS total,');
  conexao.SQL.Add('    GROUP_CONCAT(codigo) AS ids');
  conexao.SQL.Add('FROM (');
  conexao.SQL.Add('    SELECT ');
  conexao.SQL.Add('        CASE ');
  conexao.SQL.Add
    ('            WHEN nome IS NULL OR nome = "" THEN "__SEM_NOME__"');
  conexao.SQL.Add('            ELSE UPPER(TRIM(nome))');
  conexao.SQL.Add('        END AS nome_norm,');
  conexao.SQL.Add('        CASE');
  conexao.SQL.Add
    ('            WHEN cpf IS NOT NULL AND cpf <> "" THEN REPLACE(REPLACE(REPLACE(cpf, ".", ""), "-", ""), " ", "")');
  conexao.SQL.Add
    ('            WHEN celular IS NOT NULL AND celular <> "" THEN REPLACE(REPLACE(REPLACE(REPLACE(celular, "(", ""), ")", ""), "-", ""), " ", "")');
  conexao.SQL.Add
    ('            WHEN celular_wpp IS NOT NULL AND celular_wpp <> "" THEN REPLACE(REPLACE(REPLACE(REPLACE(celular_wpp, "(", ""), ")", ""), "-", ""), " ", "")');
  conexao.SQL.Add('            ELSE ""');
  conexao.SQL.Add('        END AS contato_norm,');
  conexao.SQL.Add('');
  conexao.SQL.Add('        codigo');
  conexao.SQL.Add('    FROM cliente');
  conexao.SQL.Add(') AS t');
  conexao.SQL.Add('GROUP BY nome_norm, contato_norm');
  conexao.SQL.Add('HAVING COUNT(*) > 1;');

  dados := TFDMemTable.Create(nil);
  dados.LoadFromJSON(conexao.ConsultaSQL);
  if dados.RecordCount > 0 then
  begin
    while not dados.Eof do
    begin
      CodigoCliente := MaiorValorDaLista(dados.FieldByName('ids').AsString);

      if nomeTabela.RecordCount > 0 then
      begin
        nomeTabela.First;
        while not nomeTabela.Eof do
        begin
          conexao.SQL.Add('update ' + nomeTabela.FieldByName('tabela').AsString
            + ' set codigo_cliente = :cliente where codigo_cliente in (' +
            dados.FieldByName('ids').AsString + ')');
          conexao.Parametros('cliente', CodigoCliente);
          conexao.ExecuteSQL;
          nomeTabela.Next;
        end;
      end;
      conexao.SQL.Add
        ('update cliente_endereco set codigo_cliente = :codigo where codigo in ('
        + dados.FieldByName('ids').AsString + ')');
      conexao.Parametros('codigo', CodigoCliente);
      conexao.ExecuteSQL;

      conexao.SQL.Add('delete from cliente where codigo in (' +
        ValoresSemMaior(dados.FieldByName('ids').AsString) + ')');
      conexao.ExecuteSQL;

      dados.Next;
    end;
  end;

  dados.Free;
  nomeTabela.Free;
  conexao.Free;

end;

function TSQL.MaiorValorDaLista(const Lista: string): Integer;
var
  Partes: TArray<string>;
  I, N, Maior: Integer;
begin
  Result := 0;
  if Trim(Lista) = '' then
    Exit;

  Partes := Lista.Split([',']);
  Maior := Low(Integer);

  for I := 0 to High(Partes) do
  begin
    if TryStrToInt(Trim(Partes[I]), N) then
      if N > Maior then
        Maior := N;
  end;

  Result := Maior;
end;

procedure TSQL.MigrarDadosWhatsappParaConfig;
var
  conexao: TConexao;
  QryOrigem, QryInsert: TFDQuery;
  I: Integer;
  Chave, Valor: string;
begin
  conexao := TConexao.Create('MigrarDadosWhatsappParaConfig');
  QryOrigem := conexao.CriaQRY;
  QryInsert := conexao.CriaQRY;
  // pega os dados da tabela antiga
  QryOrigem.SQL.Text := 'SELECT * FROM dados_whatsapp LIMIT 1';
  QryOrigem.Open;
  if not QryOrigem.IsEmpty then
  begin
    for I := 0 to QryOrigem.FieldCount - 1 do
    begin
      Chave := QryOrigem.Fields[I].FieldName;
      Valor := QryOrigem.Fields[I].AsString;
      QryInsert.SQL.Text := 'INSERT INTO configuracoes (chave, valor) ' +
        'VALUES (:chave, :valor) ' + 'ON DUPLICATE KEY UPDATE valor = :valor';
      QryInsert.ParamByName('chave').AsString := LowerCase(Chave);
      QryInsert.ParamByName('valor').AsString := Valor;
      QryInsert.ExecSQL;
    end;
  end;
  QryInsert.Free;
  QryOrigem.Free;
end;

procedure TSQL.ProcessaHistoricoCliente(DataBase: TDate);
var
  conexao: TConexao;
  DataAtual: TDate;
  AnoInicial, MesInicial, Dia: Word;
  AnoAtual, MesAtual: Word;
  Ano, Mes: Integer;
  DataInicioMes, DataFimMes: TDate;
  tabela: String;
  dados: TFDMemTable;
begin
  conexao := TConexao.Create('ProcessaHistoricoCliente');
  try
    DataAtual := Date; // hoje

    DecodeDate(DataBase, AnoInicial, MesInicial, Dia);
    DecodeDate(DataAtual, AnoAtual, MesAtual, Dia);

    // Loop do ano/m�s inicial at� o ano/m�s anterior ao atual
    Ano := AnoInicial;
    Mes := MesInicial;

    while (Ano < AnoAtual) or ((Ano = AnoAtual) and (Mes < MesAtual)) do
    begin
      // Monta in�cio e fim do m�s
      DataInicioMes := EncodeDate(Ano, Mes, 1);
      tabela := 'pedido_' + Ano.ToString + '_' + FormatFloat('00', Mes);
      dados := TFDMemTable.Create(nil);
      conexao.SQL.Add('SELECT ');
      conexao.SQL.Add('    codigo_cliente,    ');
      conexao.SQL.Add('    COUNT(*) AS total_pedidos,');
      conexao.SQL.Add('    SUM(valor_total_pedido) AS total_valor_pedidos,');
      conexao.SQL.Add
        ('    SUM(CASE WHEN status = 0 THEN 1 ELSE 0 END) AS qtd_cancelados,');
      conexao.SQL.Add
        ('    SUM(CASE WHEN status = 0 THEN valor_total_pedido ELSE 0 END) AS valor_cancelado,');
      conexao.SQL.Add
        ('    SUM(CASE WHEN status <> 0 THEN 1 ELSE 0 END) AS qtd_finalizados,');
      conexao.SQL.Add
        ('    SUM(CASE WHEN status <> 0 THEN valor_total_pedido ELSE 0 END) AS valor_finalizado,');
      conexao.SQL.Add('	MAX(data_pedido) as ultimo');
      conexao.SQL.Add('FROM pedido');
      conexao.SQL.Add('GROUP BY codigo_cliente');
      conexao.SQL.Add('ORDER BY total_pedidos DESC');
      dados.LoadFromJSON(conexao.ConsultaSQL);

      if dados.RecordCount > 0 then
      begin
        while not dados.Eof do
        begin

          conexao.SQL.Add
            ('update cliente set total_cancelados = total_cancelados+ :total_cancelados, total_efetivados = total_efetivados + :total_efetivados,');
          conexao.SQL.Add
            ('valor_total_cancelado = valor_total_cancelado + :valor_total_cancelado, valor_total_pedidos = valor_total_pedidos + :valor_total_pedidos,');
          conexao.SQL.Add
            ('data_ultima_atualizacao = :data where codigo = :codigo and data_ultima_atualizacao < :data');
          conexao.Parametros('total_cancelados',
            dados.FieldByName('qtd_cancelados').AsInteger);
          conexao.Parametros('total_efetivados',
            dados.FieldByName('qtd_finalizados').AsInteger);
          conexao.Parametros('valor_total_cancelado',
            dados.FieldByName('valor_cancelado').AsFloat);
          conexao.Parametros('valor_total_pedidos',
            dados.FieldByName('valor_finalizado').AsFloat);
          conexao.Parametros('codigo', dados.FieldByName('codigo_cliente')
            .AsInteger);
          conexao.Parametros('data', dados.FieldByName('ultimo').AsString);
          conexao.ExecuteSQL;

          dados.Next;
        end;
      end;

      dados.Free;

      // Pr�ximo m�s
      Inc(Mes);
      if Mes > 12 then
      begin
        Mes := 1;
        Inc(Ano);
      end;
    end;

  finally
    conexao.Free;
  end;
end;

function TSQL.UltimoCodigo(tabela, campo: String): string;
var
  conexao: TConexao;
begin
  conexao := TConexao.Create('uSQL');
  conexao.SQL.Add('SELECT ifnull(MAX(' + campo +
    ')+1,0) AS codigo,0 as zero FROM ' + tabela);
  Result := conexao.FieldByName('codigo');
  conexao.Free;
end;

function TSQL.ValoresSemMaior(const Lista: string): string;
var
  Partes: TArray<string>;
  I, N, Maior: Integer;
  ResultList: TStringList;
begin
  Result := '';

  if Trim(Lista) = '' then
    Exit;

  Partes := Lista.Split([',']);
  Maior := Low(Integer);

  // Primeiro: descobrir o maior valor
  for I := 0 to High(Partes) do
    if TryStrToInt(Trim(Partes[I]), N) then
      if N > Maior then
        Maior := N;

  // Segundo: montar lista sem os valores iguais ao maior
  ResultList := TStringList.Create;
  try
    ResultList.Delimiter := ',';
    ResultList.StrictDelimiter := True;

    for I := 0 to High(Partes) do
    begin
      if TryStrToInt(Trim(Partes[I]), N) then
      begin
        if N <> Maior then
          ResultList.Add(IntToStr(N));
      end;
    end;

    Result := ResultList.DelimitedText;
  finally
    ResultList.Free;
  end;
end;

procedure TSQL.VerificaAtualizacao;
var
  conexao: TConexao;
begin

  conexao := TConexao.Create('TConexao');
  conexao.SQL.Add('SET GLOBAL max_connections = 1000;');
  conexao.ExecuteSQL;
  conexao.Free;

  if not VerificaSQL then
  begin

    if Assigned(SeTiverAtualizacao) then
      SeTiverAtualizacao;
    MemoLog.Lines.Add('Nova atualiza��o dispon�vel!');
    // AtualizaBanco;
    iniciaSerieNFCE;
  end
  else
  begin
    if Assigned(seNaoTiverAtualizacao) then
      seNaoTiverAtualizacao;

    StatusAtualizacao := 1;

    MemoLog.Lines.Clear;
    iniciaSerieNFCE;

  end;
end;

function TSQL.VerificaSQL: Boolean;
var
  conexao: TConexao;
begin
  Result := False;

  conexao := TConexao.Create('uSQL');

  conexao.SQL.Add('select max(versaosql) as maior, 0 as zero from meu_sql');

  try
    UltimoSQLBanco := conexao.FieldByName('maior');
  except
    UltimoSQLBanco := 0;
  end;
  Result := UltimoSQLBanco = StrToInt(VersaoExe);

  conexao.Free;
  MemoLog.Lines.Clear;
  MemoLog.Lines.Add('Verificando Atualiza��es . . .');
end;

procedure TSQL.CarregarClassTribSeed;
var
  Arquivos: array [0 .. 4] of String;
  Arquivo: String;
  Lista: TStringList;
  Conteudo: String;
  Comando: String;
  I: Integer;
  C: Char;
  DentroTexto: Boolean;
begin
  Arquivos[0] := ExtractFilePath(ParamStr(0)) +
    'src\sql\fiscal_ibs_cbs_class_trib_seed.sql';
  Arquivos[1] := ExtractFilePath(ParamStr(0)) +
    'fiscal_ibs_cbs_class_trib_seed.sql';
  Arquivos[2] := GetCurrentDir + '\src\sql\fiscal_ibs_cbs_class_trib_seed.sql';
  Arquivos[3] := GetCurrentDir + '\fiscal_ibs_cbs_class_trib_seed.sql';
  Arquivos[4] := 'src\sql\fiscal_ibs_cbs_class_trib_seed.sql';

  Arquivo := '';
  for I := Low(Arquivos) to High(Arquivos) do
  begin
    if FileExists(Arquivos[I]) then
    begin
      Arquivo := Arquivos[I];
      Break;
    end;
  end;

  if Arquivo = '' then
    Exit;

  Lista := TStringList.Create;
  try
    Lista.LoadFromFile(Arquivo, TEncoding.UTF8);
    Conteudo := Lista.Text;
  finally
    Lista.Free;
  end;

  Comando := '';
  DentroTexto := False;
  I := 1;
  while I <= Length(Conteudo) do
  begin
    C := Conteudo[I];

    if C = '''' then
    begin
      Comando := Comando + C;
      if DentroTexto and (I < Length(Conteudo)) and (Conteudo[I + 1] = '''')
      then
      begin
        Inc(I);
        Comando := Comando + Conteudo[I];
      end
      else
        DentroTexto := not DentroTexto;
    end
    else if (C = ';') and (not DentroTexto) then
    begin
      if Trim(Comando) <> '' then
        ExecultaSQL(Trim(Comando));
      Comando := '';
    end
    else
      Comando := Comando + C;

    Inc(I);
  end;

  if Trim(Comando) <> '' then
    ExecultaSQL(Trim(Comando));
end;

procedure TSQL.Banco(Versao: Integer);
var
  SQL: String;
  tabela: String;
  campo: String;
begin
  ExecultaSQL
    ('create table geradores ( tabela varchar(255) not null, sequencial integer);');
  ExecultaSQL('SET sql_mode=(SELECT REPLACE(@@sql_mode,' +
    QuotedStr('ONLY_FULL_GROUP_BY') + ',' + QuotedStr('') + '));');
  case Versao of
    1:
      begin
        ExecultaSQL
          ('CREATE TABLE MEU_SQL (IDSQL INTEGER,VERSAOSQL INTEGER, SQLUSADOSQL BLOB, ERROSQL BLOB, DATASQL DATE, HORASQL TIME, STATUSSQL VARCHAR(15));');

      end;
    2:
      begin
        ExecultaSQL
          ('CREATE TABLE ATUALIZACAOAPP (    VERSAOAPP       VARCHAR(20),    VERSAOMINIMA    VARCHAR(20),    ORIGEMDOWNLOAD  VARCHAR(255));');
      end;
    3:
      begin
        ExecultaSQL
          ('CREATE TABLE status_pedido (id int NOT NULL, descricao varchar(255) DEFAULT NULL, PRIMARY KEY (id));');

        ExecultaSQL
          ('INSERT INTO status_pedido VALUES (0,"Cancelado"),(1,"Em Espera"),(2,"Em Produ��o"),(3,"Pronto"),(4,"Dispon�vel Para Retirada"),(5,"Saiu Para Entrega"),(6,"Finalizado"),(7,"Faturado");');
      end;
    4:
      begin
        ExecultaSQL('alter table impressao_caixa add tipo integer;');
      end;
    5:
      begin
        ExecultaSQL('update tipo_sabor set ativo = 0 where nome not in (' +
          QuotedStr('Promo��o') + ',' + QuotedStr('Tradicional') + ',' +
          QuotedStr('Especial') + ',' + QuotedStr('Doce') + ')');
      end;
    6:
      begin
        SQL := 'create table caixa_receber(';
        SQL := SQL + ' id integer not null,';
        SQL := SQL + ' primary key(id),';
        SQL := SQL + ' id_caixa integer,';
        SQL := SQL + ' id_cliente integer,';
        SQL := SQL + ' id_pedido integer,';
        SQL := SQL + ' id_tipo_pagamento integer,';
        SQL := SQL + ' data date,';
        SQL := SQL + ' hora time,';
        SQL := SQL + ' valor float,';
        SQL := SQL + ' status integer,';
        SQL := SQL + ' observacao varchar(200));';
        ExecultaSQL(SQL);
      end;
    7:
      begin
        ExecultaSQL('alter table tipo_pagamento add tipo_chave_pix integer;');
        ExecultaSQL('alter table tipo_pagamento add chave_pix varchar(250);');
        ExecultaSQL
          ('alter table tipo_pagamento add chave_recebedor varchar(250);');
        ExecultaSQL('alter table pedido add wpp_pix integer;');
        ExecultaSQL('alter table pedido add wpp_status integer;');
        ExecultaSQL('alter table tipo_pagamento add movimentacao integer;');
      end;
    8:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add senha_gerencia varchar(50);');

        ExecultaSQL
          ('update tipo_pagamento set movimentacao = 1 where movimentacao is null');
      end;
    9:
      begin
        ExecultaSQL('alter table pedido add gerou_pontos_fidelidade integer');
      end;
    10:
      begin
        ExecultaSQL('alter table cliente add fidelidade_ponto integer');
        ExecultaSQL('alter table cliente add fidelidade_desconto float');
        ExecultaSQL('alter table tipo_produto add user_id integer');
      end;
    11:
      begin
        ExecultaSQL
          ('update produto set saldo_atual = 0 where saldo_atual < 0 ');
      end;
    12:
      begin
        ExecultaSQL
          ('create table pix(id integer,id_pedido integer,valor real,creatdatahora datetime,expdatahora datetime,transacao varchar(500),transacao_mp varchar(50));')
      end;
    13:
      begin
        ExecultaSQL
          ('create table ingredientes_estoque(id integer,id_ingredientes integer,data date,hora time,tipo integer,quantidade real,custo_total real,custo real);');
        ExecultaSQL
          ('alter table pro_adi_personalizado_sabores add id_ingredientes integer;');
        ExecultaSQL('drop table ingredientes');
        ExecultaSQL('drop table produto_ingredientes');
        ExecultaSQL
          ('create table produto_ingredientes(id integer,id_produto integer,id_ingredientes integer,quantidade real)');
        ExecultaSQL
          ('create table ingredientes (id integer,descricao varchar(200),unidade varchar(10));');
      end;
    14:
      begin
        ExecultaSQL
          ('create table conversao(id integer,tipo integer,codigo_tipo integer,un_de varchar(20),un_para varchar(20),valor real);');

      end;
    15:
      begin
        ExecultaSQL('alter table dados_whatsapp add cor_fundo varchar(255);');
        ExecultaSQL('alter table dados_whatsapp add cor_fonte varchar(255);');
      end;
    16:
      begin
        ExecultaSQL
          ('alter table pro_adi_personalizado_sabores add quantidade_ingredientes float');
      end;
    17:
      begin
        ExecultaSQL('alter table pedido add mp varchar(255)');
        ExecultaSQL('alter table motoboy add acesso_site varchar(50)');
      end;
    18:
      begin
        ExecultaSQL('alter table pedido add id_ifood varchar(255);');
        ExecultaSQL('alter table pedido add status_ifood varchar(255);');
        ExecultaSQL('alter table tipo_produto add id_ifood varchar(255);');
        ExecultaSQL('alter table produto add id_ifood varchar(255);');
        ExecultaSQL('alter table produto add valor_ifood real;');
        ExecultaSQL
          ('alter table pedido add status_ifood_descricao varchar(255);');
      end;
    19:
      begin
        ExecultaSQL
          ('alter table pro_adi_personalizado add id_ifood varchar(255);');
        ExecultaSQL
          ('alter table pro_adi_personalizado_sabores add id_ifood varchar(255);');
        ExecultaSQL('alter table produto add foto_ifood varchar(255);');
        ExecultaSQL('alter table pedido add order_ifood varchar(50);');
        ExecultaSQL('alter table pedido add desc_desconto_ifood varchar(255);');
        ExecultaSQL('alter table pedido add agendada_ifood timestamp;');
        ExecultaSQL('alter table pedido add estimada_ifood timestamp;');
      end;
    20:
      begin
        SQL := 'create table pedido_status(';
        SQL := SQL + ' id integer,';
        SQL := SQL + ' id_pedido integer,';
        SQL := SQL + ' id_status integer,';
        SQL := SQL + ' horario timestamp);';
        ExecultaSQL(SQL);
      end;
    21:
      begin
        ExecultaSQL('delete from status_pedido where descricao = ' +
          QuotedStr('Faturado'));
        ExecultaSQL('alter table produto add position integer');
        ExecultaSQL('alter table produto add pessoas integer;');
        ExecultaSQL('alter table produto add valor_desconto real;');
        ExecultaSQL('alter table produto add percentual_desconto real;');

      end;
    22:
      begin
        ExecultaSQL('alter table pedido_produtos add id_caixa integer');
        ExecultaSQL('alter table pedido_produtos add id_pedido integer');
      end;
    24:
      begin
        ExecultaSQL('alter table produto add un varchar(50)');
        ExecultaSQL('alter table produto add ncm integer default 0');
        ExecultaSQL('alter table produto add cest integer default 0');
        ExecultaSQL('alter table produto add cfop integer default 0');
        ExecultaSQL('alter table produto add cstipi integer default 0');
        ExecultaSQL('alter table produto add csticms integer default 0');
        ExecultaSQL('alter table produto add cstpis integer default 0');
        ExecultaSQL('alter table produto add cstcofins integer default 0');
        ExecultaSQL('alter table produto add csosn integer default 0');
        ExecultaSQL('alter table produto add icms real default 0');
        ExecultaSQL('alter table produto add ipi real default 0');
        ExecultaSQL('alter table produto add pis real default 0');
        ExecultaSQL('alter table produto add cofins real default 0');
        ExecultaSQL('alter table produto add frete real default 0');

        ExecultaSQL('alter table pedido add nfce_emite integer default 0;');
        ExecultaSQL('alter table pedido add nfce_chave varchar(55);');
        ExecultaSQL('alter table pedido add nfce_protocolo varchar(55);');
        ExecultaSQL('alter table pedido add nfce_ambiente varchar(55);');
        ExecultaSQL('alter table pedido add nfce_numero varchar(55);');
        ExecultaSQL('alter table pedido add nfce_lote varchar(55);');
        ExecultaSQL
          ('create table nfce_numeracao(numero integer,lote integer);');

        ExecultaSQL('alter table dados_whatsapp add cnpj varchar(50);');
        ExecultaSQL('alter table dados_whatsapp add ie varchar(50);');
        ExecultaSQL('alter table dados_whatsapp add razao varchar(100);');
        ExecultaSQL('alter table dados_whatsapp add fone varchar(50);');
        ExecultaSQL('alter table dados_whatsapp add codcidade integer;');
        ExecultaSQL('alter table dados_whatsapp add nfce integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add nfce_ifood integer default 0;');

      end;
    25:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add imprimir_cozinha_site integer default 0;');
      end;
    26:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add marketin integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_segmento integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_desc real default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_tipo_desc integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_min real default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_qtd real default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_seg integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_ter integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_qua integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_qui integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_sex integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_sab integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_dom integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add marketin_link varchar(255)');
        ExecultaSQL
          ('alter table dados_whatsapp add homologacao integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add cozinha_apenas_mesa integer default 0;');
        ExecultaSQL('alter table dados_whatsapp add tipo integer default 0;');
      end;
    27:
      begin
        SQL := 'create table marketing(id integer not null auto_increment,';
        SQL := SQL +
          'data date,validade date,cupom varchar(50),valor real,id_cliente integer,pedido integer,status integer,primary key (id));';
        ExecultaSQL(SQL);
      end;
    28:
      begin
        ExecultaSQL('alter table motoboy add id_site integer default 0;');
        ExecultaSQL
          ('alter table motoboy add modificado_site integer default 0;');
      end;
    29:
      begin
        ExecultaSQL('CREATE INDEX codigo ON produto(codigo);');
        ExecultaSQL
          ('CREATE INDEX codigo_pedido_produto ON pedido_produto_sap(codigo_pedido_produto);');
        ExecultaSQL('CREATE INDEX id_mesa ON mesa(id_mesa);');
        ExecultaSQL('CREATE INDEX id_mesa_tipo ON mesa_tipo(id_mesa_tipo);');
        ExecultaSQL('CREATE INDEX id ON sabores_completo(id);');
        ExecultaSQL('CREATE INDEX codigo ON pedido(codigo);');
        ExecultaSQL('CREATE INDEX status ON pedido(status);');
        ExecultaSQL('CREATE INDEX id_ficha ON pedido(id_ficha);');
        ExecultaSQL('CREATE INDEX data_pedido ON pedido(data_pedido);');
        ExecultaSQL('CREATE INDEX id_ifood ON pedido(id_ifood);');
        ExecultaSQL('CREATE INDEX hora_pedido ON pedido(hora_pedido);');
        ExecultaSQL('CREATE INDEX id ON caixa(id);');
        ExecultaSQL('CREATE INDEX data_abertura ON caixa(data_abertura);');
        ExecultaSQL('CREATE INDEX status ON caixa(status);');
        ExecultaSQL('CREATE INDEX id ON caixa_movimento(id);');
        ExecultaSQL('CREATE INDEX id_caixa ON caixa_movimento(id_caixa);');

      end;
    30:
      begin
        ExecultaSQL('alter table pedido add partner varchar(50)');
      end;
    31:
      begin
        ExecultaSQL('alter table produto add fidelidade integer default 0');
      end;
    32:
      begin
        ExecultaSQL('alter table pedido add servico double default 0');
        ExecultaSQL('alter table pedido add cpf varchar(20)');
        ExecultaSQL('alter table pedido add nome varchar(50)');
      end;
    33:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add contabilidade integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add emailcontabilidade varchar(100)');
        SQL := ' create table contabilidade(';
        SQL := SQL + ' id integer not null,';
        SQL := SQL + ' data_envio date,';
        SQL := SQL + ' data varchar(50),';
        SQL := SQL + ' status integer,';
        SQL := SQL + ' erro varchar(250));';
        ExecultaSQL(SQL);

      end;
    34:
      begin
        ExecultaSQL('alter table tipo_produto add local integer default 0');

        ExecultaSQL('alter table produto add dias integer default 0;');
        ExecultaSQL('alter table produto add segunda integer default 1;');
        ExecultaSQL('alter table produto add terca integer default 1;');
        ExecultaSQL('alter table produto add quarta integer default 1;');
        ExecultaSQL('alter table produto add quinta integer default 1;');
        ExecultaSQL('alter table produto add sexta integer default 1;');
        ExecultaSQL('alter table produto add sabado integer default 1;');
        ExecultaSQL('alter table produto add domingo integer default 1;');

      end;
    35:
      begin
        ExecultaSQL('ALTER TABLE cliente MODIFY COLUMN celular VARCHAR(20);');
        ExecultaSQL('alter table caixa_movimento add id_cliente integer');
        ExecultaSQL('alter table caixa_receber add pago real default 0;');
        ExecultaSQL
          ('alter table caixa_movimento add impressao integer default 0');
        ExecultaSQL('CREATE INDEX codigo_pedido ON pedido(codigo);');
        ExecultaSQL
          ('alter table pedido_produtos add hora datetime default current_timestamp;');
        ExecultaSQL('alter table mesa add descricao varchar(255)');
        ExecultaSQL('alter table dados_whatsapp add comanda integer;');
      end;
    36:
      begin
        ExecultaSQL
          ('create table qrcod_pix (base64 blob,status integer,valor real);');
        ExecultaSQL('alter table pedido_produtos add vl_delivery real;');
      end;
    37:
      begin
        ExecultaSQL('alter table usuario add dashboard integer default 1;');
        ExecultaSQL('alter table usuario add estoque integer default 1;');
        ExecultaSQL('alter table usuario add cad_mesa integer default 1;');
        ExecultaSQL('alter table usuario add cad_motoboy integer default 1;');
        ExecultaSQL('alter table usuario add cad_taxa integer default 1;');
        ExecultaSQL
          ('alter table usuario add cad_impressora integer default 1;');
        ExecultaSQL('alter table usuario add cad_cupom integer default 1;');
        ExecultaSQL('alter table usuario add cad_prod integer default 1;');
        ExecultaSQL('alter table usuario add cad_paga integer default 1;');
        ExecultaSQL('alter table usuario add cad_cli integer default 1;');
        ExecultaSQL('alter table usuario add cad_pedido integer default 1;');
        ExecultaSQL('alter table usuario add desconto integer default 1;');
        ExecultaSQL('alter table usuario add param integer default 1;');
        ExecultaSQL('alter table usuario add caixa integer default 1;');

      end;
    38:
      begin
        ExecultaSQL('alter table usuario add cancelar integer default 1;');
      end;
    39:
      begin

        ExecultaSQL('alter table pedido add tempo_estimado integer default 0;');
        ExecultaSQL
          ('alter table tipo_produto add tempo_estimado integer default 0;');

      end;
    40:
      begin
        ExecultaSQL
          ('alter table pro_adi_personalizado_sabores add id_prod_estoque integer;');
        ExecultaSQL('alter table pedido add usuario integer');
      end;
    41:
      begin
        ExecultaSQL('ALTER TABLE produto MODIFY COLUMN cest VARCHAR(10);');
      end;
    42:
      begin
        ExecultaSQL
          ('alter table caixa_receber add impressao integer default 0');
        ExecultaSQL
          ('alter table dados_whatsapp add estoque_wpp_celular varchar(25);');
        ExecultaSQL
          ('alter table dados_whatsapp add estoque_min_recomendado integer default 30;');
        ExecultaSQL('alter table dados_whatsapp add estoque_wpp date;');
        ExecultaSQL('alter table produto add estoque_min real;');
      end;
    43:
      begin
        ExecultaSQL
          ('create table agent (id varchar(18) not null,primary key(id),datahora datetime,status integer);');
        ExecultaSQL('alter table agent add nome varchar(50);');
      end;
    44:
      begin
        ExecultaSQL('ALTER TABLE produto ALTER COLUMN cest SET DEFAULT ' +
          QuotedStr('0') + ';');
        ExecultaSQL('alter table pedido add ifood_phone varchar(50)');
        ExecultaSQL('alter table pedido add ifood_localizador varchar(50)');
        ExecultaSQL('alter table pedido add ifood_pedido varchar(50)');
      end;
    45:
      begin
        ExecultaSQL('alter table usuario add garcom integer default 0;');
      end;
    46:
      begin
        ExecultaSQL
          ('create table horario (dia_da_sema varchar(3),abertura time,fechamento time,status integer)');
      end;
    47:
      begin
        ExecultaSQL
          ('CREATE TABLE mensagem ( dia varchar(20), texto longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci)');
        ExecultaSQL
          ('ALTER SCHEMA DEFAULT CHARACTER SET utf8mb4  DEFAULT COLLATE utf8mb4_unicode_ci;');
      end;
    48:
      begin
        ExecultaSQL('alter table dados_whatsapp add certificado varchar(255);');
        ExecultaSQL('alter table dados_whatsapp add ambiente integer;');
        ExecultaSQL('alter table dados_whatsapp add forma_emissao integer;');
        ExecultaSQL('alter table dados_whatsapp add tipo_empresa integer;');
        ExecultaSQL
          ('alter table dados_whatsapp add id_token_scs varchar(255);');
        ExecultaSQL('alter table dados_whatsapp add token_scs varchar(255);');
      end;
    49:
      begin
        SQL := 'create table funcionario (id integer not null,nome varchar(50),celular varchar(15),';
        SQL := SQL +
          'funcao integer,valor double,perc_goopedir integer,perc_ifood integer,id_motoboy integer,dias varchar(50),ativo integer);';
        ExecultaSQL(SQL);
      end;
    50:
      begin
        ExecultaSQL
          ('alter table mensagem add imagem longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
      end;
    51:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add caminho_cache varchar(255)');
      end;
    52:
      begin
        ExecultaSQL
          ('ALTER TABLE produto MODIFY nome_produto VARCHAR(255) CHARACTER SET utf8 COLLATE utf8_general_ci;');
      end;
    53:
      begin
        ExecultaSQL('delete from impressao_pedido_produto');
        ExecultaSQL
          ('ALTER TABLE impressao_pedido_produto CHANGE COLUMN id_pedido id_pedido INT NOT NULL , ADD PRIMARY KEY (id_pedido);');
      end;
    54:
      begin
        ExecultaSQL
          ('create table mensagem_whatsapp (numero varchar(50) not null, primary key (numero), data date);');
        ExecultaSQL('ALTER TABLE mensagem_whatsapp ADD UNIQUE (numero);');
        ExecultaSQL('alter table dados_whatsapp add localizacao varchar(255);');

      end;
    55:
      begin
        // tabela := 'pedido_produtos';
        // campo := 'codigo';
        //
        // SQL := 'ALTER TABLE ' + tabela + ' DROP PRIMARY KEY;';
        // ExecultaSQL(SQL);
        // SQL := 'ALTER TABLE ' + tabela + ' MODIFY COLUMN ' + campo +
        // ' INT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST, AUTO_INCREMENT = ' +
        // UltimoCodigo(tabela, campo) + ';';
        // ExecultaSQL(SQL);
        //
        // tabela := 'pedido_produto_sap';
        // campo := 'id';
        // SQL := 'ALTER TABLE ' + tabela + ' DROP PRIMARY KEY;';
        // ExecultaSQL(SQL);
        // SQL := 'ALTER TABLE ' + tabela + ' MODIFY COLUMN ' + campo +
        // ' INT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST, AUTO_INCREMENT = ' +
        // UltimoCodigo(tabela, campo) + ';';
        // ExecultaSQL(SQL);
        //
        // tabela := 'impressao_pedido_produto';
        // campo := 'id';
        // SQL := 'ALTER TABLE ' + tabela + ' DROP PRIMARY KEY;';
        // ExecultaSQL(SQL);
        // SQL := 'ALTER TABLE ' + tabela + ' MODIFY COLUMN ' + campo +
        // ' INT NOT NULL AUTO_INCREMENT PRIMARY KEY FIRST, AUTO_INCREMENT = ' +
        // UltimoCodigo(tabela, campo) + ';';
        // ExecultaSQL(SQL);
        //
        // ExecultaSQL
        // ('alter table dados_whatsapp add caminho_purge varchar(255)');

        // UltimoCodigo
      end;
    56:
      begin
        ExecultaSQL('delete from geradores');
        ExecultaSQL('ALTER TABLE `geradores` ADD PRIMARY KEY (`tabela`);');
      end;
    57:
      begin
        ExecultaSQL('alter table dados_whatsapp add oculta_categoria integer');
      end;
    58:
      begin
        ExecultaSQL('alter table pedido add url varchar(255);');
      end;
    59:
      begin
        SQL := 'create table caixa_movimento_produto(';
        SQL := SQL + ' id integer not null,';
        SQL := SQL + ' primary key(id),';
        SQL := SQL + ' id_caixa_movimento integer not null,';
        SQL := SQL + ' id_pedido_produto integer not null,';
        SQL := SQL + ' quantidade double,';
        SQL := SQL + ' valor double);';
        ExecultaSQL(SQL);
      end;
    60:
      begin
        ExecultaSQL('alter table produto add novidade integer');
      end;
    61:
      begin
        ExecultaSQL('alter table dados_whatsapp add msg_massa integer');
      end;
    62:
      begin
        ExecultaSQL('alter table produto add vembuscar integer;');
        ExecultaSQL('alter table produto add delivery integer;');
      end;
    63:
      begin
        ExecultaSQL
          ('alter table pedido_produtos add selecionado integer default 0;');
      end;
    64:
      begin
        ExecultaSQL
          ('ALTER TABLE `mesa` CHANGE COLUMN `tot_mesa` `tot_mesa` DOUBLE NULL DEFAULT NULL ;');
      end;
    65:
      begin
        ExecultaSQL('alter table pedido_produtos add fracao double;');
        ExecultaSQL('alter table pedido_produtos add pessoas double;');
      end;
    66:
      begin
        ExecultaSQL
          ('ALTER TABLE `pedido_motoboy` DROP PRIMARY KEY, ADD PRIMARY KEY (`codigo`, `codigo_pedido`)');
      end;
    67:
      begin
        SQL := 'create table mensagem_massa (';
        SQL := SQL + ' id integer not null,';
        SQL := SQL + ' primary key(id),';
        SQL := SQL + ' celular varchar(20),';
        SQL := SQL + ' datahora datetime,';
        SQL := SQL + ' dia_da_semana varchar(10));';
        ExecultaSQL(SQL);
      end;
    68:
      begin
        ExecultaSQL
          ('alter table pedido add nfce_sinc_contabilidade integer default 0');
        ExecultaSQL('alter table pedido add nfce_data date;');
        ExecultaSQL('alter table pedido add nfce_hora time;');
      end;
    69:
      begin
        // S� fiz 1x
        ExecultaSQL('alter table pedido add nfce_imprimir integer default 0');
      end;
    70:
      begin
        ExecultaSQL('alter table sabores_completo add id_ifood varchar(50)');
      end;
    71:
      begin
        ExecultaSQL
          ('alter table tipo_produto add borda_topo_direito integer default 10;');
        ExecultaSQL
          ('alter table tipo_produto add borda_topo_esquerdo integer default 10;');
        ExecultaSQL
          ('alter table tipo_produto add borda_inferior_direito integer default 10;');
        ExecultaSQL
          ('alter table tipo_produto add borda_inferior_esquerdo integer default 10;');
        ExecultaSQL
          ('alter table tipo_produto add espacamento integer default 1;');
        ExecultaSQL
          ('alter table tipo_produto add fonte_nome integer default 16;');
        ExecultaSQL
          ('alter table tipo_produto add fonte_descricao integer default 13;');
        ExecultaSQL('alter table tipo_produto add cor_fundo varchar(20);');
        ExecultaSQL('alter table tipo_produto add cor_nome varchar(20);');
        ExecultaSQL('alter table tipo_produto add cor_descricao varchar(20);');
        ExecultaSQL('alter table tipo_produto add descricao_cat varchar(255);');
        ExecultaSQL
          ('ALTER TABLE tipo_produto CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');
        ExecultaSQL
          ('ALTER TABLE tipo_produto MODIFY descricao VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');
        ExecultaSQL
          ('ALTER TABLE tipo_produto MODIFY descricao_cat VARCHAR(255) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');
        ExecultaSQL
          ('ALTER TABLE produto MODIFY descricao VARCHAR(2555) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');

      end;
    72:
      begin
        // ExecultaSQL('SET GLOBAL wait_timeout = 60;');
        // ExecultaSQL('SET GLOBAL interactive_timeout = 60;');
      end;
    73:
      begin
        ExecultaSQL
          ('create table conexao(id integer not null,datahora timestamp,mysql varchar(255));');
      end;
    74:
      begin
        ExecultaSQL('update motoboy set modificado_site = 0 where codigo > 0');
      end;
    75:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add fidelidade_status integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add fidelidade_ponto integer default 1;');
        ExecultaSQL
          ('alter table dados_whatsapp add fidelidade_pontos real default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add fidelidade_desc real default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add fidelidade_min real default 0;');
        ExecultaSQL('alter table dados_whatsapp add cor_fundo varchar(20);');
        ExecultaSQL('alter table dados_whatsapp add cor_fonte varchar(20);');
      end;
    76:
      begin
        ExecultaSQL
          ('create table pedido_nfce(id integer not null,id_pedido integer,chave varchar(50),protocolo varchar(50),caminho varchar(2555))');
      end;
    77:
      begin
        ExecultaSQL
          ('CREATE TABLE impressao_pedido_nfce (id INTEGER NOT NULL AUTO_INCREMENT,PRIMARY KEY (id),id_pedido INTEGER,solicitacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP,status INTEGER DEFAULT 0,impressao TIMESTAMP);');
      end;
    78:
      begin
      end;
    79:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add retirada integer default 1;');
        ExecultaSQL
          ('alter table dados_whatsapp add delivery integer default 1;');
      end;
    80:
      begin
        // Contagem Estoque
        if Assigned(AtualizaEstoque) then
          AtualizaEstoque;
      end;
    81:
      begin
        ExecultaSQL('alter table ingredientes add saldo real default 0;');
        ExecultaSQL('alter table ingredientes add tipo integer default 1;');
        ExecultaSQL('alter table ingredientes add custo real default 0;');
        ExecultaSQL('alter table ingredientes add custo_medio real default 0;');
        ExecultaSQL
          ('alter table ingredientes add custo_ultimo real default 0;');
        SQL := 'create table ingredientes_ficha (';
        SQL := SQL + ' id integer not null,';
        SQL := SQL + ' primary key(id),';
        SQL := SQL + ' id_ingrediente integer,';
        SQL := SQL + ' id_composicao  integer,';
        SQL := SQL + 'quantidade real);';
        ExecultaSQL(SQL);
        ExecultaSQL('alter table ingredientes add quantidade real default 0;');

      end;
    82:
      begin
        ExecultaSQL('alter table mesa add hora timestamp;');
        ExecultaSQL
          ('alter table dados_whatsapp add cx_resumido integer default 1;');
      end;
    83:
      begin
        ExecultaSQL('alter table pedido_produtos add html longtext');
      end;
    84:
      begin
        SQL := 'CREATE TABLE cmv (';
        SQL := SQL + '  id INT NOT NULL AUTO_INCREMENT,';
        SQL := SQL + '  PRIMARY KEY(id),';
        SQL := SQL + '  codigo_produto integer,';
        SQL := SQL + '  custo_ingrediente DOUBLE,';
        SQL := SQL + '  custo_indiretos DOUBLE,';
        SQL := SQL + '  percentual_imposto DOUBLE,';
        SQL := SQL + '  percentual_cartao DOUBLE,';
        SQL := SQL + '  percentual_ifood DOUBLE,';
        SQL := SQL + '  percentual_lucro DOUBLE,';
        SQL := SQL + '  valor_imposto DOUBLE,';
        SQL := SQL + '  valor_cartao DOUBLE,';
        SQL := SQL + '  valor_ifood DOUBLE,';
        SQL := SQL + '  valor_lucro DOUBLE,';
        SQL := SQL + '  preco_sugerido DOUBLE,';
        SQL := SQL + '  data_inicial TIMESTAMP DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + '  data_final TIMESTAMP';
        SQL := SQL + ');';
        ExecultaSQL(SQL);
      end;
    85:
      begin
        ExecultaSQL('alter table produto add new boolean default true;');
        ExecultaSQL('update produto set new = false;');
      end;
    86:
      begin
        //
        ExecultaSQL('alter table taxa_entrega add tempo DOUBLE default 0;');
      end;
    87:
      begin

        ExecultaSQL
          ('alter table dados_whatsapp add token_ifood varchar(2555);');
        //
      end;
    88:
      begin
        ExecultaSQL
          ('alter table pedido_produtos add datahora_deletado timestamp');
        ExecultaSQL('alter table pedido add datahora_deletado timestamp');
        ExecultaSQL('alter table usuario add campanha integer default 0');

      end;
    89:
      begin
        ExecultaSQL('alter table pedido add latitude real default 0;');
        ExecultaSQL('alter table pedido add longitude real default 0;');
      end;
    90:
      begin
        ExecultaSQL
          ('create table ifood_connect (id integer not null,primary key(id),name varchar(20),merchantid varchar(255), data timestamp,token varchar(2555),error blob,link blob,autenticacao varchar(10));');
        ExecultaSQL('insert into ifood_connect (id) values (1);');
        ExecultaSQL('insert into ifood_connect (id) values (2);');
        ExecultaSQL('alter table pedido add ifood integer;');
      end;
    91:
      begin
        // alter table caixa add id_site integer;
        ExecultaSQL('alter table produto add userid integer;');
      end;
    92:
      begin
        ExecultaSQL
          ('create table index_pedido (id integer, primary key(id), referencia varchar(255));');
      end;
    93:
      begin
        ExecultaSQL
          ('insert into status_pedido (id,descricao) values (9,"Aguardando Confirma��o")');
      end;
    94:
      begin
        ExecultaSQL
          ('insert into usuario (codigo,nome) values (-1,"Qrcod Mesa")');
        ExecultaSQL('insert into usuario (codigo,nome) values (-2,"Site")');
      end;
    95:
      begin
        ExecultaSQL
          ('create table fila (id integer not null auto_increment,primary key (id),origem varchar(255),json longtext)');
      end;
    96:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add exclusao_itens integer default 0;');
      end;
    97:
      begin
        SQL := 'ALTER TABLE `dados_whatsapp`';
        SQL := SQL +
          ' CHANGE COLUMN `mensagem_inicio` `mensagem_inicio` VARCHAR(2555) CHARACTER SET "utf8mb4" COLLATE "utf8mb4_unicode_ci" NULL DEFAULT NULL ;';
        ExecultaSQL(SQL);

      end;
    98:
      begin
        ExecultaSQL('alter table caixa add id_site integer default 0;');
        ExecultaSQL('alter table caixa add link varchar(255);');
      end;
    99:
      begin
        ExecultaSQL('alter table tipo_produto add url varchar(255);');
        ExecultaSQL('alter table tipo_produto add opacidade integer;');
      end;
    100:
      begin
        ExecultaSQL('alter table dados_whatsapp add banner longtext');
      end;
    101:
      begin
        ExecultaSQL('alter table dados_whatsapp add pixel varchar(20);');
      end;
    102:
      begin
        ExecultaSQL('alter table pedido add servico_percentual double;');
      end;
    103:
      begin
        SQL := ' CREATE TABLE despesas (';
        SQL := SQL + ' id int NOT NULL AUTO_INCREMENT,';
        SQL := SQL + ' categoria int NOT NULL,';
        SQL := SQL +
          ' descricao varchar(100) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL + ' valor decimal(10,2) DEFAULT NULL,';
        SQL := SQL + ' parcelas int DEFAULT NULL,';
        SQL := SQL + ' parcela int DEFAULT NULL,';
        SQL := SQL + ' vencimento date DEFAULT NULL,';
        SQL := SQL + ' status int DEFAULT NULL,';
        SQL := SQL + ' excluida int DEFAULT "0",';
        SQL := SQL + ' PRIMARY KEY (id))';
        ExecultaSQL(SQL);

        SQL := ' CREATE TABLE descricao (';
        SQL := SQL + ' id int NOT NULL AUTO_INCREMENT,';
        SQL := SQL +
          ' descricao varchar(45) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL + ' PRIMARY KEY (id))  ';
        ExecultaSQL(SQL);

      end;
    104:
      begin
        ExecultaSQL
          ('ALTER TABLE tipo_pagamento CHANGE COLUMN tipo_chave_pix tipo_chave_pix VARCHAR(50) NULL ;');
      end;
    105:
      begin
        ExecultaSQL
          ('ALTER TABLE tipo_pagamento CHANGE COLUMN tipo_chave_pix tipo_chave_pix VARCHAR(255)');
        ExecultaSQL
          ('ALTER TABLE pedido_produtos ADD COLUMN usuario_deletado INT NULL AFTER datahora_deletado;');
        ExecultaSQL
          ('ALTER TABLE pedido_produtos ADD COLUMN usuario_pedido INT NULL AFTER datahora_deletado;');
        ExecultaSQL('ALTER TABLE pedido ADD COLUMN usuario_deletado INT NULL');

      end;
    106:
      begin

        SQL := 'CREATE TABLE balanca ( ';
        SQL := SQL + '    id INT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '    modelo VARCHAR(100),';
        SQL := SQL + '    descricao VARCHAR(255),';
        SQL := SQL + '    protocolo VARCHAR(100),';
        SQL := SQL + '    porta VARCHAR(50),';
        SQL := SQL + '    peso DECIMAL(10, 3),';
        SQL := SQL + '    tara DECIMAL(10, 3),';
        SQL := SQL + '    ultima_sinc TIMESTAMP NULL DEFAULT NULL';
        SQL := SQL + ');';
        ExecultaSQL(SQL);
        ExecultaSQL('alter table produto add referencia varchar(50);');
      end;
    107:
      begin
        ExecultaSQL('alter table produto add tipo_produto_site varchar(50)');
        ExecultaSQL('alter table usuario add percentual float default 0;');
      end;
    108:
      begin
        ExecultaSQL('alter table usuario add impressora integer default 0');
        ExecultaSQL('alter table pedido_nfce add path varchar(2555);');
      end;
    109:
      begin
        ExecultaSQL('delete from impressao_pedido_nfce');
        ExecultaSQL
          ('ALTER TABLE `impressao_pedido_nfce` CHANGE COLUMN `id_pedido` `id_pedido` INT NOT NULL , ADD UNIQUE INDEX `id_pedido_UNIQUE` (`id_pedido` ASC) VISIBLE;');
        ExecultaSQL('alter table produto add tiposite varchar(2555);');
      end;
    110:
      begin
        ExecultaSQL('alter table pro_adi_personalizado add categoria integer');
        ExecultaSQL('alter table produto add tiposite integer');
      end;
    111:
      begin
        ExecultaSQL
          ('CREATE INDEX idx_pedido_usuario_status_caixa ON pedido (usuario, codigo_pedido_dia, status, id_caixa, codigo);');
        ExecultaSQL
          ('CREATE INDEX idx_cmp_produto ON caixa_movimento_produto (id_pedido_produto);');
        ExecultaSQL
          ('CREATE INDEX idx_sap_produto ON pedido_produto_sap (codigo_pedido_produto);');
        ExecultaSQL
          ('CREATE INDEX idx_pedido_produtos_codigo_pedido ON pedido_produtos (codigo_pedido);');
        ExecultaSQL('CREATE INDEX idx_index_pedido_id ON index_pedido (id);');
        ExecultaSQL
          ('CREATE INDEX idx_produto_grupo_ativo ON produto (codigo_grupo, ativo);');
        ExecultaSQL('CREATE INDEX idx_balanca_id ON balanca (id);');
        ExecultaSQL
          ('CREATE INDEX idx_produto_codigo_grupo ON produto (codigo_grupo);');

      end;
    112:
      begin
        ExecultaSQL('alter table produto add referencia varchar(50)');
        ExecultaSQL('alter table produto add tiposite varchar(50)');
        ExecultaSQL
          ('ALTER TABLE tipo_pagamento CHANGE COLUMN tipo_chave_pix tipo_chave_pix VARCHAR(250) NULL DEFAULT "";');
        ExecultaSQL
          ('ALTER TABLE pro_adi_personalizado ADD COLUMN categoria INT NULL;');

      end;
    113:
      begin
        ExecultaSQL('ALTER TABLE index_pedido ADD COLUMN count INT default 0;');
        ExecultaSQL('alter table cliente add pedidos integer default 0;');
      end;
    114:
      begin
        SQL := 'create table banner (';
        SQL := SQL + ' id integer not null auto_increment,';
        SQL := SQL + ' priamry key(id),';
        SQL := SQL + ' descricao varchar(50),';
        SQL := SQL + ' dia_semana varchar(50),';
        SQL := SQL + ' status integer,';
        SQL := SQL + ' link varchar(255));';
        ExecultaSQL(SQL);

        SQL := ' create table pedido_painel (';
        SQL := SQL + ' id integer not null auto_increment,';
        SQL := SQL + ' datahora timestamp,';
        SQL := SQL + ' id_pedido integer,';
        SQL := SQL + ' quantidade integer,';
        SQL := SQL + ' id_painel  integer,';
        SQL := SQL + ' primary key(id));';
        ExecultaSQL(SQL);

        SQL := 'create table painel( ';
        SQL := SQL + 'id integer not null auto_increment,';
        SQL := SQL + 'primary key(id),';
        SQL := SQL + 'descricao varchar(50),';
        SQL := SQL + 'tipo integer);';
        ExecultaSQL(SQL);

        ExecultaSQL('alter table banner add tempo integer default 60');
        ExecultaSQL('alter table banner add paineis varchar(255);');
      end;
    115:
      begin
        SQL := 'ALTER TABLE pedido_painel ';
        SQL := SQL +
          ' CHANGE COLUMN `datahora` `datahora` TIMESTAMP NULL DEFAULT current_timestamp() ,';
        SQL := SQL +
          ' CHANGE COLUMN `quantidade` `quantidade` INT NULL DEFAULT 0 ;';
        ExecultaSQL(SQL);
      end;
    116:
      begin
        ExecultaSQL('alter table sabores_completo add url varchar(255)');
      end;
    117:
      begin
        ExecultaSQL
          ('ALTER TABLE pro_adi_personalizado_sabores ADD COLUMN alerta INT NULL DEFAULT 0;');
        ExecultaSQL
          ('ALTER TABLE produto ADD COLUMN alerta INT NULL DEFAULT 0;');
        ExecultaSQL
          ('ALTER TABLE sabores_completo ADD COLUMN alerta INT NULL DEFAULT 0;');
        ExecultaSQL('alter table produto add deletado integer NULL DEFAULT 0;');
        SQL := 'CREATE TABLE `produto_pendencia` (';
        SQL := SQL + '  `id` INT NOT NULL AUTO_INCREMENT,';
        SQL := SQL + '  `id_produto` INT NULL,';
        SQL := SQL + '  `detalhe` VARCHAR(225) NULL,';
        SQL := SQL + '  `observacao` VARCHAR(255) NULL,';
        SQL := SQL + '  PRIMARY KEY (`id`));';
        ExecultaSQL(SQL);

        ExecultaSQL
          ('alter table pro_adi_personalizado_sabores add deletado integer DEFAULT 0');

        ExecultaSQL
          ('ALTER TABLE pedido_produtos ADD COLUMN tempo_liberacao INT NULL DEFAULT 2');
      end;
    118:
      begin
        ExecultaSQL
          ('alter table pro_adi_personalizado add deletado integer DEFAULT 0');
      end;
    119:
      begin
        SQL := ' CREATE TABLE banner (';
        SQL := SQL + '   id int NOT NULL AUTO_INCREMENT,';
        SQL := SQL +
          '   descricao varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL +
          '   dia_semana varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL + '   status int DEFAULT NULL,';
        SQL := SQL +
          '   link varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL + '   tempo int DEFAULT 60,';
        SQL := SQL +
          '   paines varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL +
          '   paineis varchar(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL + '   PRIMARY KEY (id)';
        SQL := SQL + ' )';
        ExecultaSQL(SQL);
        SQL := ' CREATE TABLE painel (';
        SQL := SQL + '   id int NOT NULL AUTO_INCREMENT,';
        SQL := SQL +
          '   descricao varchar(50) COLLATE utf8mb4_unicode_ci DEFAULT NULL,';
        SQL := SQL + '   tipo int DEFAULT NULL,';
        SQL := SQL + '   PRIMARY KEY (id)';
        SQL := SQL + ' )';
        ExecultaSQL(SQL);
      end;
    120:
      begin
        ExecultaSQL
          ('alter table pro_adi_personalizado add categoria integer DEFAULT 0');
        ExecultaSQL
          ('ALTER TABLE cliente CHANGE COLUMN data_nascimento data_nascimento VARCHAR(10) NULL DEFAULT NULL ;');

      end;
    121:
      begin
        SQL := SQL + ' CREATE TABLE favoritos (';
        SQL := SQL + '   id INT NOT NULL AUTO_INCREMENT,';
        SQL := SQL + '   usuario INT NULL,';
        SQL := SQL + '   descricao VARCHAR(45) NULL,';
        SQL := SQL + '   rota VARCHAR(45) NULL,';
        SQL := SQL + '   icone VARCHAR(45) NULL DEFAULT "FaHamburger",';
        SQL := SQL + '   ordem INT NULL,';
        SQL := SQL + '   ativo INT NULL,';
        SQL := SQL + '   created_at DATETIME NULL,';
        SQL := SQL + '   updated_at DATETIME NULL,';
        SQL := SQL + '   PRIMARY KEY (id));';
        ExecultaSQL(SQL);
      end;
    122:
      begin
        ExecultaSQL('alter table pedido_produtos add uuid varchar(50)');
      end;
    123:
      begin
        // ============================================================
        // TABELA: fornecedor
        // ============================================================
        SQL := 'CREATE TABLE fornecedor (';
        SQL := SQL + '    id CHAR(36) PRIMARY KEY,';
        SQL := SQL + '    cnpj VARCHAR(20) NOT NULL UNIQUE,';
        SQL := SQL + '    nome VARCHAR(255) NOT NULL,';
        SQL := SQL + '    inscricao_estadual VARCHAR(30),';
        SQL := SQL + '    endereco VARCHAR(255),';
        SQL := SQL + '    municipio VARCHAR(100),';
        SQL := SQL + '    uf CHAR(2),';
        SQL := SQL + '    email VARCHAR(150),';
        SQL := SQL + '    telefone VARCHAR(50),';
        SQL := SQL + '    tipo_fornecedor ENUM("PJ", "PF") DEFAULT "PJ",';
        SQL := SQL + '    criado_em DATETIME DEFAULT CURRENT_TIMESTAMP';
        SQL := SQL + ');';
        ExecultaSQL(SQL);
        // ============================================================
        // TABELA: fornecedor_item (cat�logo do fornecedor)
        // ============================================================
        SQL := ' CREATE TABLE fornecedor_item (';
        SQL := SQL + '     id CHAR(36) PRIMARY KEY,';
        SQL := SQL + '     fornecedor_id CHAR(36) NOT NULL,';
        SQL := SQL + '     cprod VARCHAR(60) NOT NULL,';
        SQL := SQL + '     cEAN VARCHAR(20),';
        SQL := SQL + '     xProd VARCHAR(255),';
        SQL := SQL + '     NCM VARCHAR(20),';
        SQL := SQL + '     CEST VARCHAR(10),';
        SQL := SQL + '     CFOP VARCHAR(10),';
        SQL := SQL + '     uCom VARCHAR(10),';
        SQL := SQL + '     ultimo BOOLEAN DEFAULT TRUE,';
        SQL := SQL + '     tabela_vinculo ENUM("produto", "ingrediente"),';
        SQL := SQL + '     campo_vinculo VARCHAR(100),';
        SQL := SQL + '     codigo_vinculo CHAR(36),';
        SQL := SQL + '     ativo BOOLEAN DEFAULT TRUE,';
        SQL := SQL + '     criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL +
          '     FOREIGN KEY (fornecedor_id) REFERENCES fornecedor(id)';
        SQL := SQL + ' );';
        ExecultaSQL(SQL);
        // ============================================================
        // TABELA: unidade_conversao
        // ============================================================
        SQL := ' CREATE TABLE unidade_conversao (';
        SQL := SQL + '     id CHAR(36) PRIMARY KEY,';
        SQL := SQL + '     fornecedor_item_id CHAR(36) NOT NULL,';
        SQL := SQL + '     unidade_fornecedor VARCHAR(10) NOT NULL,';
        SQL := SQL + '     unidade_interna VARCHAR(10) NOT NULL,';
        SQL := SQL + '     fator DECIMAL(15,6) NOT NULL,';
        SQL := SQL + '     criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL +
          '     FOREIGN KEY (fornecedor_item_id) REFERENCES fornecedor_item(id)';
        SQL := SQL + ' );';
        ExecultaSQL(SQL);
        // ============================================================
        // TABELA: nota_fiscal
        // ============================================================
        SQL := ' CREATE TABLE nota_fiscal (';
        SQL := SQL + '     id CHAR(36) PRIMARY KEY,';
        SQL := SQL + '     fornecedor_id CHAR(36) NOT NULL,';
        SQL := SQL + '     serie VARCHAR(10),';
        SQL := SQL + '     numero VARCHAR(20),';
        SQL := SQL + '     chave VARCHAR(44) UNIQUE,';
        SQL := SQL + '     modelo VARCHAR(5),';
        SQL := SQL + '     tipo ENUM("NF", "NFCe"),';
        SQL := SQL + '     data_emissao DATETIME,';
        SQL := SQL + '     data_entrada DATETIME,';
        SQL := SQL + '     vNF DECIMAL(15,2),';
        SQL := SQL + '     vFrete DECIMAL(15,2),';
        SQL := SQL + '     vDesc DECIMAL(15,2),';
        SQL := SQL + '     vOutro DECIMAL(15,2),';
        SQL := SQL + '     xml_original LONGTEXT,';
        SQL := SQL +
          '     status_importacao ENUM("pendente", "processada", "erro") DEFAULT "pendente",';
        SQL := SQL + '     criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL +
          '     FOREIGN KEY (fornecedor_id) REFERENCES fornecedor(id)';
        SQL := SQL + ' );';
        ExecultaSQL(SQL);
        // ============================================================
        // TABELA: nota_fiscal_item
        // ============================================================
        SQL := ' CREATE TABLE nota_fiscal_item (';
        SQL := SQL + '     id CHAR(36) PRIMARY KEY,';
        SQL := SQL + '     nota_fiscal_id CHAR(36) NOT NULL,';
        SQL := SQL + '     fornecedor_item_id CHAR(36),';
        SQL := SQL + '     cProd VARCHAR(60),';
        SQL := SQL + '     xProd VARCHAR(255),';
        SQL := SQL + '     NCM VARCHAR(20),';
        SQL := SQL + '     CFOP VARCHAR(10),';
        SQL := SQL + '     qCom DECIMAL(15,6),';
        SQL := SQL + '     uCom VARCHAR(10),';
        SQL := SQL + '     vUnCom DECIMAL(15,6),';
        SQL := SQL + '     vProd DECIMAL(15,2),';
        SQL := SQL + '     vDesc DECIMAL(15,2),';
        SQL := SQL + '     vFrete DECIMAL(15,2),';
        SQL := SQL + '     vOutro DECIMAL(15,2),';
        SQL := SQL +
          '     vTotal DECIMAL(15,2) GENERATED ALWAYS AS (vProd - IFNULL(vDesc,0) + IFNULL(vFrete,0) + IFNULL(vOutro,0)) STORED,';
        SQL := SQL + '     uTrib VARCHAR(10),';
        SQL := SQL + '     criado_em DATETIME DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL +
          '     FOREIGN KEY (nota_fiscal_id) REFERENCES nota_fiscal(id),';
        SQL := SQL +
          '     FOREIGN KEY (fornecedor_item_id) REFERENCES fornecedor_item(id)';
        SQL := SQL + ' );';
        ExecultaSQL(SQL);
        ExecultaSQL
          ('insert into usuario (codigo,nome) values (-1,"QRCOD MESA");');
        ExecultaSQL
          ('insert into usuario (codigo,nome) values (-2,"PEDIDO SITE");');
      end;
    124:
      begin
        ExecultaSQL
          ('ALTER TABLE fornecedor_item ADD COLUMN fator FLOAT NULL DEFAULT 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add mensagem_conclusao varchar(2555);');
        ExecultaSQL
          ('alter table dados_whatsapp add conclusao_envio_range varchar(20) default "3,24";');
      end;
    125:
      begin
        SQL := 'CREATE TABLE dfe_consulta (';
        SQL := SQL + '  id INT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '  cnpj_empresa VARCHAR(18) NOT NULL,';
        SQL := SQL + '  data_consulta DATE NOT NULL,';
        SQL := SQL + '  hora_consulta TIME NOT NULL,';
        SQL := SQL + '  ultimo_nsu VARCHAR(15) NOT NULL,';
        SQL := SQL + '  qtd_documentos INT DEFAULT 0,';
        SQL := SQL +
          '  ambiente ENUM("producao", "homologacao") DEFAULT "producao",';
        SQL := SQL + '  criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;';
        ExecultaSQL(SQL);
        SQL := ' CREATE TABLE dfe_documento (';
        SQL := SQL + '   id INT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '   id_consulta INT NOT NULL,';
        SQL := SQL + '   nsu VARCHAR(15) NOT NULL,';
        SQL := SQL + '   chave VARCHAR(44) NOT NULL,';
        SQL := SQL + '   cnpj_emitente VARCHAR(18),';
        SQL := SQL + '   nome_emitente VARCHAR(150),';
        SQL := SQL + '   valor DECIMAL(15,2),';
        SQL := SQL + '   data_emissao DATETIME,';
        SQL := SQL + '   situacao VARCHAR(30),';
        SQL := SQL + '   xml_base64 LONGTEXT,';
        SQL := SQL + '   tipo ENUM("nfe", "evento", "resumo") DEFAULT "nfe",';
        SQL := SQL + '   criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + '   UNIQUE KEY uk_chave (chave),';
        SQL := SQL + '   INDEX idx_nsu (nsu),';
        SQL := SQL +
          '   CONSTRAINT fk_dfe_consulta FOREIGN KEY (id_consulta) REFERENCES dfe_consulta(id)';
        SQL := SQL + '     ON DELETE CASCADE';
        SQL := SQL +
          ' ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;';
        ExecultaSQL(SQL);
        ExecultaSQL
          ('ALTER TABLE despesas ADD COLUMN `chave_nota` VARCHAR(45);');
      end;
    126:
      begin
        ExecultaSQL
          ('CREATE INDEX idx_estoque_ingrediente_id_desc ON ingredientes_estoque (id_ingredientes, id DESC);');
        ExecultaSQL
          ('CREATE INDEX idx_estoque_ingrediente_quantidade ON ingredientes_estoque (id_ingredientes, quantidade);');
        ExecultaSQL
          ('CREATE INDEX idx_cliente_endereco_cliente_codigo ON cliente_endereco (codigo_cliente, codigo DESC);');
        ExecultaSQL('CREATE INDEX idx_cliente_nome ON cliente (nome);');
        ExecultaSQL
          ('CREATE INDEX idx_cliente_endereco_cliente_codigo ON cliente_endereco (codigo_cliente, codigo);');
        ExecultaSQL
          ('ALTER TABLE fornecedor_item ADD COLUMN fator FLOAT NULL DEFAULT 1;');
        ExecultaSQL('delete from produto_estoque');
        ExecultaSQL('alter table produto_estoque add transacao varchar(255)');
        ExecultaSQL
          ('ALTER TABLE produto_estoque ADD UNIQUE KEY unq_pedido_item (transacao);');
      end;
    127:
      begin
        SQL := 'CREATE TABLE IF NOT EXISTS bancos (';
        SQL := SQL + ' id INT NOT NULL AUTO_INCREMENT,';
        SQL := SQL + ' codigo INT NOT NULL,';
        SQL := SQL + ' ispb VARCHAR(20) DEFAULT NULL,';
        SQL := SQL + ' nome VARCHAR(150) DEFAULT NULL,';
        SQL := SQL + ' nome_completo VARCHAR(255) DEFAULT NULL,';
        SQL := SQL + ' ativo INT DEFAULT 1,';
        SQL := SQL + ' criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + ' atualizado_em TIMESTAMP NULL DEFAULT NULL,';
        SQL := SQL + ' PRIMARY KEY (id),';
        SQL := SQL + ' UNIQUE KEY uk_bancos_codigo (codigo),';
        SQL := SQL + ' INDEX idx_bancos_nome (nome),';
        SQL := SQL + ' INDEX idx_bancos_ativo (ativo)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;';
        ExecultaSQL(SQL);

      end;
    128:
      begin
        SQL := ' ALTER TABLE `cliente`';
        SQL := SQL + ' DROP COLUMN `fidelidade_desconto`,';
        SQL := SQL + ' DROP COLUMN `fidelidade_ponto`,';
        SQL := SQL + ' DROP COLUMN `id_cliente_site`,';
        SQL := SQL + ' DROP COLUMN `cashback_saldo`,';
        SQL := SQL + ' DROP COLUMN `oculto`,';
        SQL := SQL + ' DROP COLUMN `salvar_dados`,';
        SQL := SQL + ' DROP COLUMN `bloqueado`;';
        ExecultaSQL(SQL);

        SQL := ' ALTER TABLE cliente';
        SQL := SQL + ' ADD total_pedidos INT DEFAULT 0,';
        SQL := SQL + ' ADD total_cancelados INT DEFAULT 0,';
        SQL := SQL + ' ADD total_efetivados INT DEFAULT 0,';
        SQL := SQL + ' ADD percentual_cancelado DECIMAL(5,2) DEFAULT 0,';
        SQL := SQL + ' ADD percentual_efetivado DECIMAL(5,2) DEFAULT 0,';
        SQL := SQL + ' ADD nota_cliente DECIMAL(3,2) DEFAULT 0,';
        SQL := SQL + ' ADD valor_total_pedidos DECIMAL(10,2) DEFAULT 0,';
        SQL := SQL + ' ADD valor_total_cancelado DECIMAL(10,2) DEFAULT 0,';
        SQL := SQL + ' ADD data_ultima_atualizacao DATETIME NULL;';
        ExecultaSQL(SQL);
        ExecultaSQL
          ('update cliente set total_efetivados = 0, valor_total_pedidos = 0, data_ultima_atualizacao = "2000-01-01"');
      end;
    129:
      begin
        ExecultaSQL('drop trigger trg_pedido_produtos_after_insert');
        ExecultaSQL
          ('ALTER TABLE impressao_pedido_produto MODIFY id INT NOT NULL AUTO_INCREMENT;');
        SQL := ' CREATE TRIGGER trg_pedido_produtos_after_insert ';
        SQL := SQL + ' AFTER INSERT ON pedido_produtos';
        SQL := SQL + ' FOR EACH ROW';
        SQL := SQL + ' BEGIN';
        SQL := SQL + '     INSERT INTO impressao_pedido_produto (';
        SQL := SQL + '         data_solicitacao,';
        SQL := SQL + '         hora_solicitacao,';
        SQL := SQL + '         data_impressao,';
        SQL := SQL + '         hora_impressao,';
        SQL := SQL + '         id_pedido,';
        SQL := SQL + '         status,';
        SQL := SQL + '         vias,';
        SQL := SQL + '         usuario';
        SQL := SQL + '     ) VALUES (';
        SQL := SQL + '         CURDATE(),';
        SQL := SQL + '         CURTIME(),';
        SQL := SQL + '         NULL,';
        SQL := SQL + '         NULL,';
        SQL := SQL + '         NEW.codigo,';
        SQL := SQL + '         1,';
        SQL := SQL + '         1,';
        SQL := SQL + '         NEW.usuario';
        SQL := SQL + '     );';
        SQL := SQL + ' END ';
        ExecultaSQL(SQL);
      end;
    130:
      begin
        SQL := 'CREATE TABLE IF NOT EXISTS fila_impressao (';
        SQL := SQL + ' id BIGINT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + ' pedido_id BIGINT NOT NULL,';
        SQL := SQL + ' tipo VARCHAR(50) NOT NULL,';
        SQL := SQL + ' payload LONGTEXT NULL,';
        SQL := SQL + ' status VARCHAR(20) NOT NULL DEFAULT ''PENDENTE'',';
        SQL := SQL + ' tentativas INT NOT NULL DEFAULT 0,';
        SQL := SQL + ' erro TEXT NULL,';
        SQL := SQL + ' criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + ' processado_em DATETIME NULL,';
        SQL := SQL + ' INDEX idx_fila_status_criado (status, criado_em),';
        SQL := SQL + ' INDEX idx_fila_pedido (pedido_id)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;';
        ExecultaSQL(SQL);
      end;
    131:
      begin
        ExecultaSQL('ALTER TABLE `pedido` ENGINE = InnoDB');
        CriarPrimeiraParticaoPedidoAll;

      end;
    132:
      begin
        ExecultaSQL('alter table pedido add codigoOld varchar(20)');
      end;
    133:
      begin
        ExecultaSQL('alter table dados_whatsapp add USAR_BALANCA integer');
        ExecultaSQL('alter table dados_whatsapp add MENU_TV integer');
      end;
    134:
      begin
        SQL := 'create table config_temporaria( ';
        SQL := SQL + 'id varchar(1), job_id varchar(255))';
        ExecultaSQL(SQL);
        ExecultaSQL('insert into config_temporaria (id) values ("1")');
        ExecultaSQL
          ('alter table pro_adi_personalizado_sabores add url varchar(255)');
        ExecultaSQL('alter table pedido add nfce_status varchar(20)');
        ExecultaSQL('alter table pedido add nfce_tentativas int default 0');
        ExecultaSQL('alter table pedido add nfce_lock DATETIME NULL');
      end;
    135:
      begin
        SQL := ' CREATE TABLE produto_combo_config (';
        SQL := SQL + '     id BIGINT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '     produto_combo_id BIGINT NOT NULL, ';
        SQL := SQL +
          '     data_criacao DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL +
          '     status ENUM("ATIVO","INATIVO") NOT NULL DEFAULT "ATIVO",';
        SQL := SQL + '     hash_calculo CHAR(64) NULL, ';
        SQL := SQL + '     INDEX idx_combo_status (produto_combo_id, status)';
        SQL := SQL + ' );';

        ExecultaSQL(SQL);

        SQL := 'CREATE TABLE produto_combo_item (';
        SQL := SQL + '     id BIGINT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '     combo_config_id BIGINT NOT NULL,';
        SQL := SQL + '     produto_id BIGINT NOT NULL,';
        SQL := SQL + '     ratio DECIMAL(10,8) NOT NULL,';
        SQL := SQL + '     base_value DECIMAL(10,2) NOT NULL,';
        SQL := SQL + '     FOREIGN KEY (combo_config_id)';
        SQL := SQL + '         REFERENCES produto_combo_config(id)';
        SQL := SQL + '         ON DELETE CASCADE,';
        SQL := SQL +
          '     INDEX idx_combo_item (combo_config_id, produto_id));';

        ExecultaSQL(SQL);

        ExecultaSQL('alter table banner add titulo varchar(200);');
        ExecultaSQL('alter table banner add subtitulo varchar(200);');
        ExecultaSQL('alter table banner add produto integer;');

        SQL := 'CREATE TABLE alerta_sistema (';
        SQL := SQL + '    id            INT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '    tipo          ENUM(';
        SQL := SQL + '                     "CHAMAR_GARCOM",';
        SQL := SQL + '                     "ERRO_SENHA_TABLET",';
        SQL := SQL + '                     "ALERTA_SEGURANCA",';
        SQL := SQL + '                     "NFCE_ERRO",';
        SQL := SQL + '                     "OUTRO",';
        SQL := SQL + '                     "PRODUTO",';
        SQL := SQL + '                     "SISTEMA",';
        SQL := SQL + '                     "DFE",';
        SQL := SQL + '                     "ESTOQUE"';
        SQL := SQL + '                   ) NOT NULL,';
        SQL := SQL + '    origem        ENUM(';
        SQL := SQL + '                     "MESA",';
        SQL := SQL + '                     "TABLET",';
        SQL := SQL + '                     "SISTEMA",';
        SQL := SQL + '                     "NFCE",';
        SQL := SQL + '                     "USUARIO"';
        SQL := SQL + '                   ) NOT NULL,';

        SQL := SQL + '    referencia_id INT NULL, ';

        // -- ex: mesa_id, tablet_id, usuario_id
        SQL := SQL + '    status        ENUM(';
        SQL := SQL + '                     "ABERTO",';
        SQL := SQL + '                     "VISUALIZADO",';
        SQL := SQL + '                     "RESOLVIDO"';
        SQL := SQL + '                   ) DEFAULT "ABERTO",';

        SQL := SQL + '    tentativas    INT DEFAULT 0,';
        SQL := SQL + '    payload       JSON NULL,';
        // -- dados extras (ex: motivo, mensagem, ip, etc)
        SQL := SQL +
          '    data_evento   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + '    data_resolvido DATETIME NULL);';

        ExecultaSQL(SQL);

        ExecultaSQL('alter table mesa add usuario integer');

        SQL := ' CREATE TABLE menu (';
        SQL := SQL + '     id INT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '     nome VARCHAR(100) NOT NULL,';
        SQL := SQL +
          '     tipo ENUM("tablet","delivery","totem","qr","tv") NOT NULL,';
        SQL := SQL + '     ativo TINYINT(1) NOT NULL DEFAULT 1,';
        SQL := SQL +
          '     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL +
          '     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP';
        SQL := SQL + '                  ON UPDATE CURRENT_TIMESTAMP,';
        SQL := SQL + '     UNIQUE KEY uk_menu_tipo (tipo)';
        SQL := SQL + ' ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
        ExecultaSQL(SQL);
        SQL := ' CREATE TABLE menu_item (';
        SQL := SQL + '     id INT AUTO_INCREMENT PRIMARY KEY,';
        SQL := SQL + '     menu_id INT NOT NULL,';
        SQL := SQL + '     nome VARCHAR(150) NOT NULL,';
        SQL := SQL + '     pai_id INT NULL,';
        SQL := SQL + '     ordem INT NOT NULL DEFAULT 0,';
        SQL := SQL + '     produto_id INT NULL,';
        SQL := SQL + '     categoria_id INT NULL,';
        SQL := SQL + '     ativo TINYINT(1) NOT NULL DEFAULT 1,';
        SQL := SQL +
          '     created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL +
          '     updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP';
        SQL := SQL + '                  ON UPDATE CURRENT_TIMESTAMP,';
        SQL := SQL + '     CONSTRAINT fk_menu_item_menu';
        SQL := SQL + '         FOREIGN KEY (menu_id)';
        SQL := SQL + '         REFERENCES menu(id)';
        SQL := SQL + '         ON DELETE CASCADE,';
        SQL := SQL + '     CONSTRAINT fk_menu_item_pai';
        SQL := SQL + '         FOREIGN KEY (pai_id)';
        SQL := SQL + '         REFERENCES menu_item(id)';
        SQL := SQL + '         ON DELETE CASCADE,';
        SQL := SQL + '     KEY idx_menu (menu_id),';
        SQL := SQL + '     KEY idx_pai (pai_id),';
        SQL := SQL + '     KEY idx_produto (produto_id),';
        SQL := SQL + '     KEY idx_categoria (categoria_id)';
        SQL := SQL + ' ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4';
        ExecultaSQL(SQL);
        ExecultaSQL
          ('INSERT INTO menu (nome, tipo, ativo) VALUES ("Card�pio Tablet", "tablet", 1);');

      end;
    136:
      begin
        ExecultaSQL('alter table tipo_produto add destaque integer default 0');
        ExecultaSQL('insert into usuario (codigo,nome) values (-3,"Tablet")');
        ExecultaSQL('alter table cliente add data_cadastro date;');

        ExecultaSQL
          ('ALTER TABLE caixa_movimento ADD COLUMN data_hora DATETIME GENERATED ALWAYS AS (TIMESTAMP(data, hora)) STORED;');
        ExecultaSQL
          ('CREATE INDEX idx_caixa_datahora ON caixa_movimento (data_hora);');
        ExecultaSQL
          ('ALTER TABLE pedido ADD COLUMN data_hora DATETIME GENERATED ALWAYS AS (TIMESTAMP(data_pedido, hora_pedido)) STORED;');
        ExecultaSQL('CREATE INDEX idx_pedido_datahora ON pedido (data_hora);');
        ExecultaSQL
          ('ALTER TABLE cliente ADD COLUMN data_cadastro DATE NULL DEFAULT current_date()');

      end;
    137:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add tempo_preparo_delivery integer default 80');
        ExecultaSQL
          ('alter table dados_whatsapp add tempo_preparo_vembuscar integer default  65');
        ExecultaSQL
          ('alter table dados_whatsapp add tempo_preparo_mesa integer default  65');
        ExecultaSQL
          ('alter table dados_whatsapp add usar_tempo_preparo integer default  0');
        SQL := ' ALTER TABLE pedido_produtos ';
        SQL := SQL + ' ADD COLUMN preparo_tempo INT NULL DEFAULT 0 AFTER uuid,';
        SQL := SQL +
          ' ADD COLUMN preparo_hora TIMESTAMP NULL AFTER preparo_tempo';
        ExecultaSQL(SQL);
        ExecultaSQL
          ('ALTER TABLE pedido ADD COLUMN preparo_hora TIMESTAMP NULL AFTER nfce_lock');
        ExecultaSQL
          ('ALTER TABLE pedido ADD recalcula_preparo TINYINT DEFAULT 1;');

      end;
    138:
      begin
        ExecultaSQL('alter table tipo_produto add destaque integer default 0');
      end;
    139:
      begin
        ExecultaSQL('alter table menu_item add background_link varchar(255)');
      end;
    140:
      begin
        SQL := ' CREATE TABLE log_operacao (';
        SQL := SQL + '     id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,';
        SQL := SQL +
          '     data_hora DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + '     ip VARCHAR(45) NOT NULL,';
        SQL := SQL + '     usuario VARCHAR(100) NULL,';
        SQL := SQL + '     operacao VARCHAR(100) NOT NULL,';
        SQL := SQL + '     endpoint VARCHAR(255) NOT NULL,';
        SQL := SQL + '     body LONGTEXT NULL,';
        SQL := SQL + '     PRIMARY KEY (id),';
        SQL := SQL + '     INDEX idx_data_hora (data_hora),';
        SQL := SQL + '     INDEX idx_usuario (usuario),';
        SQL := SQL + '     INDEX idx_operacao (operacao)';
        SQL := SQL + ' ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;';
        ExecultaSQL(SQL);
      end;
    142:
      begin

      end;
    143:
      begin
        ExecultaSQL('alter table pedido add pedido_nfce integer default 0');
      end;
    144:
      begin
        ExecultaSQL
          ('ALTER TABLE motoboy CHANGE COLUMN acesso_site VARCHAR(255)');
        ExecultaSQL
          ('alter table pedido add ultima_interacao timestamp default current_timestamp()');
        ExecultaSQL
          ('alter table dados_whatsapp add mensagem_fora_expediente longtext');
        ExecultaSQL
          ('ALTER TABLE dados_whatsapp MODIFY mensagem_fora_expediente TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');
        ExecultaSQL
          ('ALTER TABLE dados_whatsapp MODIFY mensagem_conclusao TEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');
      end;
    145:
      begin
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY rua TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY bairro TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY cidade TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY estado TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY wpp_equipamento TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY chave TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY url_webservice TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY client_id TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY client_security TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY senha_gerencia TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY token_mp TEXT;');
        ExecultaSQL('ALTER TABLE dados_whatsapp MODIFY token_mp TEXT;');
        ExecultaSQL
          ('alter table dados_whatsapp add nfce_serie integer default 0;');
        ExecultaSQL
          ('alter table dados_whatsapp add nfce_numeracao integer default 0;');
      end;
    146:
      begin
        SQL := 'CREATE TABLE configuracoes (';
        SQL := SQL + '  chave VARCHAR(100) PRIMARY KEY,';
        SQL := SQL + '  valor TEXT';
        SQL := SQL + ') CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;';
        ExecultaSQL(SQL);
        MigrarDadosWhatsappParaConfig;
      end;
    147:
      begin
        ExecultaSQL('alter table usuario add id_caixa integer');
        ExecultaSQL('alter table pedido add cliente_count integer default 0');
        SQL := 'CREATE TABLE cliente_estatistica (';
        SQL := SQL + '    codigo_cliente INT NOT NULL,    ';
        SQL := SQL + '    pedidos INT NOT NULL DEFAULT 0,';
        SQL := SQL + '    cancelados INT NOT NULL DEFAULT 0,';
        SQL := SQL + '    finalizados INT NOT NULL DEFAULT 0,';
        SQL := SQL + '    total_pedidos DOUBLE NOT NULL DEFAULT 0,';
        SQL := SQL + '    total_cancelados DOUBLE NOT NULL DEFAULT 0,';
        SQL := SQL + '    total_finalizados DOUBLE NOT NULL DEFAULT 0,';
        SQL := SQL + '    ultimo_pedido DATETIME NULL,';
        SQL := SQL +
          '    data_atualizacao TIMESTAMP DEFAULT CURRENT_TIMESTAMP ';
        SQL := SQL + '    ON UPDATE CURRENT_TIMESTAMP,';
        SQL := SQL + '    PRIMARY KEY (codigo_cliente),';
        SQL := SQL + '    INDEX idx_ultimo_pedido (ultimo_pedido))';
        ExecultaSQL(SQL);

        ExecultaSQL
          ('CREATE INDEX idx_cliente_count ON pedido (cliente_count, codigo_cliente);');

        ExecultaSQL('CREATE INDEX idx_status ON pedido (status);');

        ExecultaSQL
          ('CREATE INDEX idx_codigo_cliente ON pedido (codigo_cliente);');
      end;
    148:
      begin
        ExecultaSQL
          ('ALTER TABLE alerta_sistema MODIFY COLUMN tipo ENUM("CHAMAR_GARCOM","ERRO_SENHA_TABLET","ALERTA_SEGURANCA","NFCE_ERRO","OUTRO","PRODUTO","SISTEMA","DFE","ESTOQUE") NOT NULL');
        ExecultaSQL
          ('ALTER TABLE alerta_sistema MODIFY COLUMN origem ENUM("MESA","TABLET","SISTEMA","NFCE","USUARIO") NOT NULL');
        ExecultaSQL('ALTER TABLE cliente ADD email_nfce varchar(255)');
        ExecultaSQL('ALTER TABLE agent add usuario integer');
        ExecultaSQL('delete from agent');

      end;
    149:
      begin
        ExecultaSQL
          ('alter table dados_whatsapp add utilizar_dfe integer default 0');
        ExecultaSQL
          ('alter table dados_whatsapp add manifestar_dfe_tipo varchar(30)');
        ExecultaSQL
          ('alter table dfe_documento add manifestada TINYINT(1) NOT NULL DEFAULT 0');
        ExecultaSQL
          ('alter table dfe_documento add manifestacao_tipo VARCHAR(30) NULL');
        ExecultaSQL
          ('alter table dfe_documento add manifestacao_status VARCHAR(40) NULL');
        ExecultaSQL
          ('alter table dfe_documento add manifestacao_origem VARCHAR(20) NULL');
        ExecultaSQL
          ('alter table dfe_documento add manifestacao_data DATETIME NULL');
        ExecultaSQL
          ('CREATE INDEX idx_dfe_manifestada ON dfe_documento (manifestada, manifestacao_status)');
      end;
    150:
      begin
        ExecultaSQL
          ('CREATE DATABASE IF NOT EXISTS `goopedir_cache` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci');
        ExecultaSQL('CREATE TABLE IF NOT EXISTS `goopedir_cache`.`cache` (' +
          'origem VARCHAR(100) NOT NULL, ' + 'chave VARCHAR(255) NOT NULL, ' +
          'dados LONGTEXT NOT NULL, ' +
          'criado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, ' +
          'atualizado_em TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, '
          + 'PRIMARY KEY (origem, chave), ' +
          'INDEX idx_cache_atualizado (atualizado_em)' +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci');
      end;
    151:
      begin
        ExecultaSQL
          ('ALTER TABLE goopedir_cache.cache ADD COLUMN expira_em DATETIME NULL');
        ExecultaSQL
          ('CREATE INDEX idx_cache_expira ON goopedir_cache.cache (expira_em)');
      end;
    152:
      begin
        SQL := 'CREATE TABLE erro_fiscal (';
        SQL := SQL + '  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,';
        SQL := SQL + '  origem VARCHAR(30) NOT NULL,';
        SQL := SQL + '  mensagem_hash CHAR(64) NOT NULL,';
        SQL := SQL + '  mensagem TEXT NOT NULL,';
        SQL := SQL + '  contador INT NOT NULL DEFAULT 1,';
        SQL := SQL +
          '  primeiro_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + '  ultimo_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + '  PRIMARY KEY (id),';
        SQL := SQL + '  UNIQUE KEY uk_erro_fiscal (origem, mensagem_hash),';
        SQL := SQL + '  INDEX idx_erro_fiscal_ultimo (ultimo_em)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci';
        ExecultaSQL(SQL);
        SQL := 'CREATE TABLE erro_fiscal_pedido (';
        SQL := SQL + '  id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,';
        SQL := SQL + '  erro_fiscal_id BIGINT UNSIGNED NOT NULL,';
        SQL := SQL + '  pedido_id INT NOT NULL,';
        SQL := SQL + '  criado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + '  PRIMARY KEY (id),';
        SQL := SQL +
          '  UNIQUE KEY uk_erro_fiscal_pedido (erro_fiscal_id, pedido_id),';
        SQL := SQL + '  INDEX idx_erro_fiscal_pedido_pedido (pedido_id),';
        SQL := SQL +
          '  CONSTRAINT fk_erro_fiscal_pedido_erro FOREIGN KEY (erro_fiscal_id) REFERENCES erro_fiscal(id) ON DELETE CASCADE';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci';
        ExecultaSQL(SQL);
      end;
    153:
      begin
        ExecultaSQL('ALTER TABLE produto DROP INDEX codigo;');
        ExecultaSQL('ALTER TABLE produto DROP INDEX idx_produto_codigo;');
        ExecultaSQL
          ('ALTER TABLE mesa ADD INDEX idx_mesa_selecionada (selecionada);');
        ExecultaSQL
          ('ALTER TABLE caixa ADD INDEX idx_caixa_usuario_status (id_usuario, status);');
      end;
    154:
      begin
        ExecultaSQL('alter table cliente add fidelidade integer');
      end;
    155:
      begin
        ExecultaSQL
          ('alter table produto add ibs_cbs_cst varchar(3) default "000"');
        ExecultaSQL
          ('alter table produto add ibs_cbs_class_trib varchar(7) default "000001"');
        ExecultaSQL
          ('alter table produto add ibs_uf_aliq decimal(10,4) default 0.1');
        ExecultaSQL
          ('alter table produto add ibs_mun_aliq decimal(10,4) default 0');
        ExecultaSQL
          ('alter table produto add cbs_aliq decimal(10,4) default 0.9');
      end;
    156:
      begin
        SQL := 'CREATE TABLE IF NOT EXISTS fiscal_ibs_cbs_cst (';
        SQL := SQL + '  cst VARCHAR(3) NOT NULL,';
        SQL := SQL + '  descricao VARCHAR(255) NOT NULL,';
        SQL := SQL + '  ind_gibscbs TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gibscbs_mono TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gred TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gdif TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gtransf_cred TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gcred_pres_ibszfm TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gajuste_compet TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfe TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfce TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_cte TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_cteos TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_bpe TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_bpetm TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nf3e TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfcom TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfse TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL +
          '  atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,';
        SQL := SQL + '  PRIMARY KEY (cst)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci';
        ExecultaSQL(SQL);

        SQL := 'CREATE TABLE IF NOT EXISTS fiscal_ibs_cbs_class_trib (';
        SQL := SQL + '  cclass_trib VARCHAR(7) NOT NULL,';
        SQL := SQL + '  cst VARCHAR(3) NOT NULL,';
        SQL := SQL + '  nome VARCHAR(255) NOT NULL,';
        SQL := SQL + '  descricao TEXT NULL,';
        SQL := SQL + '  lc_redacao TEXT NULL,';
        SQL := SQL + '  lc_214_25 VARCHAR(100) NULL,';
        SQL := SQL + '  tipo_aliquota VARCHAR(100) NULL,';
        SQL := SQL + '  pred_ibs DECIMAL(10,4) NOT NULL DEFAULT 0,';
        SQL := SQL + '  pred_cbs DECIMAL(10,4) NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_redutor_bc VARCHAR(10) NULL,';
        SQL := SQL + '  ind_gtrib_regular TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gcred_pres_oper TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gmono_padrao TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gmono_reten TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gmono_ret TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gmono_dif TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_gestorno_cred TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  credito_para TEXT NULL,';
        SQL := SQL + '  dini_vig DATE NULL,';
        SQL := SQL + '  dfim_vig DATE NULL,';
        SQL := SQL + '  data_atualizacao DATE NULL,';
        SQL := SQL + '  ind_nfe_abi TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfe TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfce TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_cte TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_cteos TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_bpe TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_bpeta TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_bpetm TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nf3e TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfse TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfse_via TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfcom TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfag TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_nfgas TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  ind_dere TINYINT NOT NULL DEFAULT 0,';
        SQL := SQL + '  anexo VARCHAR(100) NULL,';
        SQL := SQL + '  link VARCHAR(500) NULL,';
        SQL := SQL +
          '  atualizado_em DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,';
        SQL := SQL + '  PRIMARY KEY (cclass_trib),';
        SQL := SQL + '  INDEX idx_fiscal_class_trib_cst (cst),';
        SQL := SQL +
          '  CONSTRAINT fk_fiscal_class_trib_cst FOREIGN KEY (cst) REFERENCES fiscal_ibs_cbs_cst(cst)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci';
        ExecultaSQL(SQL);

        ExecultaSQL
          ('CREATE INDEX idx_produto_ibs_cbs_cst ON produto (ibs_cbs_cst)');
        ExecultaSQL
          ('CREATE INDEX idx_produto_ibs_cbs_class_trib ON produto (ibs_cbs_class_trib)');
        ExecultaSQL
          ('ALTER TABLE produto MODIFY COLUMN ibs_cbs_class_trib VARCHAR(7) DEFAULT "000001"');
        ExecultaSQL
          ('ALTER TABLE fiscal_ibs_cbs_class_trib MODIFY COLUMN cclass_trib VARCHAR(7) NOT NULL');
        ExecultaSQL
          ('ALTER TABLE fiscal_ibs_cbs_class_trib MODIFY COLUMN credito_para TEXT NULL');
        ExecultaSQL
          ('ALTER TABLE fiscal_ibs_cbs_class_trib MODIFY COLUMN credito_para TEXT NULL;');
        ExecultaSQL
          ('ALTER TABLE produto MODIFY COLUMN ibs_cbs_class_trib VARCHAR(7) DEFAULT "000001";');
        ExecultaSQL
          ('ALTER TABLE produto MODIFY COLUMN ibs_uf_aliq DECIMAL(10,4) DEFAULT 0.1;');
        ExecultaSQL
          ('ALTER TABLE produto MODIFY COLUMN cbs_aliq DECIMAL(10,4) DEFAULT 0.9;');
        ExecultaSQL
          ('UPDATE produto SET ibs_uf_aliq = 0.1 WHERE ibs_uf_aliq IS NULL OR ibs_uf_aliq = 0;');
        ExecultaSQL
          ('UPDATE produto SET cbs_aliq = 0.9 WHERE cbs_aliq IS NULL OR cbs_aliq = 0;');
        ExecultaSQL
          ('ALTER TABLE fiscal_ibs_cbs_class_trib MODIFY COLUMN cclass_trib VARCHAR(7) NOT NULL;');
        ExecultaSQL
          ('ALTER TABLE fiscal_ibs_cbs_class_trib MODIFY COLUMN credito_para TEXT NULL;');
        CarregarClassTribSeed;
      end;
    157:
      begin
        ExecultaSQL
          ('ALTER TABLE produto MODIFY COLUMN ibs_uf_aliq DECIMAL(10,4) DEFAULT 0.1;');
        ExecultaSQL
          ('ALTER TABLE produto MODIFY COLUMN cbs_aliq DECIMAL(10,4) DEFAULT 0.9;');
        ExecultaSQL
          ('UPDATE produto SET ibs_uf_aliq = 0.1 WHERE ibs_uf_aliq IS NULL OR ibs_uf_aliq = 0;');
        ExecultaSQL
          ('UPDATE produto SET cbs_aliq = 0.9 WHERE cbs_aliq IS NULL OR cbs_aliq = 0;');
      end;
    158:
      begin
        SQL := 'CREATE TABLE IF NOT EXISTS bancos (';
        SQL := SQL + ' id INT NOT NULL AUTO_INCREMENT,';
        SQL := SQL + ' codigo INT NOT NULL,';
        SQL := SQL + ' ispb VARCHAR(20) DEFAULT NULL,';
        SQL := SQL + ' nome VARCHAR(150) DEFAULT NULL,';
        SQL := SQL + ' nome_completo VARCHAR(255) DEFAULT NULL,';
        SQL := SQL + ' ativo INT DEFAULT 1,';
        SQL := SQL + ' criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + ' atualizado_em TIMESTAMP NULL DEFAULT NULL,';
        SQL := SQL + ' PRIMARY KEY (id),';
        SQL := SQL + ' UNIQUE KEY uk_bancos_codigo (codigo),';
        SQL := SQL + ' INDEX idx_bancos_nome (nome),';
        SQL := SQL + ' INDEX idx_bancos_ativo (ativo)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;';
        ExecultaSQL(SQL);

      end;
    159:
      begin
        SQL := 'CREATE TABLE IF NOT EXISTS cartoes (';
        SQL := SQL + ' id INT NOT NULL AUTO_INCREMENT,';
        SQL := SQL + ' banco_id INT NOT NULL,';
        SQL := SQL + ' nome VARCHAR(100) NOT NULL,';
        SQL := SQL + ' tipo VARCHAR(20) NOT NULL DEFAULT "credito",';
        SQL := SQL + ' melhor_dia INT DEFAULT 1,';
        SQL := SQL + ' dia_vencimento INT DEFAULT 1,';
        SQL := SQL + ' limite DECIMAL(15,2) DEFAULT 0,';
        SQL := SQL + ' limite_usado DECIMAL(15,2) DEFAULT 0,';
        SQL := SQL + ' vencimento_ano_mes VARCHAR(7) DEFAULT NULL,';
        SQL := SQL + ' ativo INT DEFAULT 1,';
        SQL := SQL + ' criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + ' atualizado_em TIMESTAMP NULL DEFAULT NULL,';
        SQL := SQL + ' PRIMARY KEY (id),';
        SQL := SQL + ' INDEX idx_cartoes_banco (banco_id),';
        SQL := SQL + ' INDEX idx_cartoes_tipo (tipo),';
        SQL := SQL + ' INDEX idx_cartoes_ativo (ativo),';
        SQL := SQL +
          ' CONSTRAINT fk_cartoes_banco FOREIGN KEY (banco_id) REFERENCES bancos(id)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;';
        ExecultaSQL(SQL);
      end;
    160:
      begin
        ExecultaSQL('ALTER TABLE despesas ADD COLUMN cartao_id INT DEFAULT 0;');
        ExecultaSQL
          ('ALTER TABLE despesas ADD COLUMN limite_cartao_retornado INT DEFAULT 0;');
        ExecultaSQL
          ('ALTER TABLE despesas ADD COLUMN recorrente INT DEFAULT 0;');
        ExecultaSQL
          ('ALTER TABLE despesas ADD COLUMN recorrencia_tipo INT DEFAULT 0;');
        ExecultaSQL
          ('ALTER TABLE despesas ADD COLUMN recorrencia_grupo VARCHAR(40) DEFAULT NULL;');
        ExecultaSQL
          ('ALTER TABLE despesas ADD COLUMN fatura_ano_mes VARCHAR(7) DEFAULT NULL;');
        ExecultaSQL
          ('CREATE INDEX idx_despesas_cartao ON despesas (cartao_id);');
        ExecultaSQL
          ('CREATE INDEX idx_despesas_recorrencia_grupo ON despesas (recorrencia_grupo);');
        ExecultaSQL
          ('CREATE INDEX idx_despesas_fatura ON despesas (fatura_ano_mes);');
      end;
    161:
      begin
        SQL := 'CREATE TABLE IF NOT EXISTS despesa_recorrencia (';
        SQL := SQL + ' id INT NOT NULL AUTO_INCREMENT,';
        SQL := SQL + ' categoria INT NOT NULL,';
        SQL := SQL + ' descricao VARCHAR(100) DEFAULT NULL,';
        SQL := SQL + ' valor DECIMAL(15,2) DEFAULT 0,';
        SQL := SQL + ' cartao_id INT DEFAULT 0,';
        SQL := SQL + ' recorrencia_tipo INT DEFAULT 3,';
        SQL := SQL + ' dia_vencimento INT DEFAULT 1,';
        SQL := SQL + ' proximo_vencimento DATE NOT NULL,';
        SQL := SQL + ' ativo INT DEFAULT 1,';
        SQL := SQL + ' chave_nota VARCHAR(45) DEFAULT NULL,';
        SQL := SQL + ' fatura_ano_mes VARCHAR(7) DEFAULT NULL,';
        SQL := SQL + ' recorrencia_grupo VARCHAR(40) NOT NULL,';
        SQL := SQL + ' criado_em TIMESTAMP DEFAULT CURRENT_TIMESTAMP,';
        SQL := SQL + ' atualizado_em TIMESTAMP NULL DEFAULT NULL,';
        SQL := SQL + ' PRIMARY KEY (id),';
        SQL := SQL +
          ' UNIQUE KEY uk_despesa_recorrencia_grupo (recorrencia_grupo),';
        SQL := SQL +
          ' INDEX idx_despesa_recorrencia_proximo (ativo, proximo_vencimento),';
        SQL := SQL + ' INDEX idx_despesa_recorrencia_cartao (cartao_id)';
        SQL := SQL +
          ') ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;';
        ExecultaSQL(SQL);
      end;
    162:
      begin
        ExecultaSQL
          ('ALTER TABLE despesas ADD COLUMN data_compra DATE DEFAULT NULL;');
        ExecultaSQL
          ('CREATE INDEX idx_despesas_data_compra ON despesas (data_compra);');
      end;
    163:
      begin
        ExecultaSQL('ALTER TABLE log_operacao ADD tempo_ms INT NULL;');
      end;
    164:
      begin
        ExecultaSQL
          ('CREATE TABLE IF NOT EXISTS configuracoes (chave VARCHAR(100) PRIMARY KEY, valor TEXT) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;');
        ExecultaSQL
          ('INSERT INTO configuracoes (chave, valor) VALUES (''atualizacao_ambiente'', ''producao'') ON DUPLICATE KEY UPDATE valor = valor;');
        ExecultaSQL
          ('INSERT INTO configuracoes (chave, valor) VALUES (''atualizacao_token'', ''IWC8cNw2RrgbL7280RSaTzzoD8LrWS3YjbhT24J8lfT'') ON DUPLICATE KEY UPDATE valor = valor;');
        ExecultaSQL
          ('INSERT INTO configuracoes (chave, valor) VALUES (''atualizacao_url'', ''https://atualizacao.goopedir.com'') ON DUPLICATE KEY UPDATE valor = valor;');
        ExecultaSQL
          ('INSERT INTO configuracoes (chave, valor) VALUES (''atualizacao_executaveis'', ''atualizador.exe;GooPedir.exe;ServicosGoopedir.exe;SiteGooPedir.exe;ImpressaoGooPedir.exe;NFCe.exe;WhatsappGoPedir.exe;psGoopedir.exe'') ON DUPLICATE KEY UPDATE valor = valor;');
      end;
    165:
      begin
        ExecultaSQL('ALTER TABLE usuario ADD COLUMN financeiro INT DEFAULT 0;');
      end;
    166:
      begin
        ExecultaSQL('ALTER TABLE usuario ADD COLUMN usuario_pai INT DEFAULT 0;');
        ExecultaSQL('CREATE INDEX idx_usuario_pai ON usuario (usuario_pai);');
      end;
    167:
      begin
        ExecultaSQL('ALTER TABLE usuario ADD COLUMN tempo_expiracao INT DEFAULT 12;');
        ExecultaSQL('alter table pedido add updated_at datetime');
      end;
    168:
      begin
        ExecultaSQL
          ('ALTER TABLE sabores_completo ADD COLUMN ultima_compra DATE NOT NULL DEFAULT ''2026-01-01'';');
        ExecultaSQL
          ('ALTER TABLE pro_adi_personalizado_sabores ADD COLUMN ultima_compra DATE NOT NULL DEFAULT ''2026-01-01'';');
        ExecultaSQL
          ('CREATE INDEX idx_sabores_completo_ultima_compra ON sabores_completo (ultima_compra);');
        ExecultaSQL
          ('CREATE INDEX idx_pro_adi_sabores_ultima_compra ON pro_adi_personalizado_sabores (ultima_compra);');
        ExecultaSQL('DROP TRIGGER IF EXISTS trg_pps_ultima_compra;');
        SQL := 'CREATE TRIGGER trg_pps_ultima_compra AFTER INSERT ON pedido_produto_sap FOR EACH ROW ' +
          'BEGIN ' +
          '  DECLARE v_produto INT DEFAULT 0; ' +
          '  DECLARE v_categoria INT DEFAULT 0; ' +
          '  DECLARE v_afetados INT DEFAULT 0; ' +
          '  SELECT COALESCE(pp.codigo_produto, 0), COALESCE(prod.codigo_grupo, 0) ' +
          '    INTO v_produto, v_categoria ' +
          '    FROM pedido_produtos pp ' +
          '    LEFT JOIN produto prod ON prod.codigo = pp.codigo_produto ' +
          '   WHERE pp.codigo = NEW.codigo_pedido_produto ' +
          '   LIMIT 1; ' +
          '  IF UPPER(COALESCE(NEW.nomeclatura, '''')) = ''SABORES'' THEN ' +
          '    UPDATE sabores_completo ' +
          '       SET ultima_compra = CURDATE() ' +
          '     WHERE id_produto = v_produto ' +
          '       AND UPPER(nome) = UPPER(COALESCE(NEW.descricao, '''')); ' +
          '  ELSE ' +
          '    UPDATE pro_adi_personalizado_sabores paps ' +
          '    JOIN pro_adi_personalizado pap ON pap.id = paps.id_pro_adi_personalizado ' +
          '       SET paps.ultima_compra = CURDATE() ' +
          '     WHERE (pap.id_produto = v_produto OR pap.categoria = v_categoria) ' +
          '       AND UPPER(pap.descricao) = UPPER(COALESCE(NEW.nomeclatura, '''')) ' +
          '       AND UPPER(paps.nome) = UPPER(COALESCE(NEW.descricao, '''')); ' +
          '    SET v_afetados = ROW_COUNT(); ' +
          '    IF v_afetados = 0 THEN ' +
          '      UPDATE sabores_completo ' +
          '         SET ultima_compra = CURDATE() ' +
          '       WHERE id_produto = v_produto ' +
          '         AND UPPER(nome) = UPPER(COALESCE(NEW.descricao, '''')); ' +
          '    END IF; ' +
          '  END IF; ' +
          'END;';
        ExecultaSQL(SQL);
      end;
    99999999:
      begin
        {


        }
      end;
  end;

end;

function TSQL.VersaoExe: String;
begin
  Result := '168';
end;

end.
