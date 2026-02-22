# Política de Privacidade do KintaMed Edge 🛡️

**Última atualização: 23 de janeiro de 2026**

O KintaMed Edge está comprometido em proteger a privacidade e a segurança dos dados dos pacientes tratados pelos Agentes Comunitários de Saúde (ACS). Esta Política de Privacidade explica nossa filosofia de dados "Zero-Cloud" e como garantimos confidencialidade absoluta em campo.

---

## 1. Filosofia de Dados Zero-Cloud
O KintaMed Edge é um aplicativo **prioritariamente offline (offline-first)**. **Não coletamos, transmitimos ou armazenamos quaisquer dados em servidores externos, provedores de nuvem ou bancos de dados de terceiros.**

Tudo o que você insere no aplicativo permanece no dispositivo físico onde o aplicativo está instalado.

## 2. Dados que Processamos Localmente
Para fornecer suporte à decisão clínica, o aplicativo processa os seguintes dados exclusivamente no seu dispositivo:
- **Dados Demográficos do Paciente**: Nome, idade, sexo, data de nascimento.
- **Dados Clínicos**: Sinais vitais (PA, SpO2, frequência cardíaca, etc.), sintomas e histórico médico.
- **Mídia Clínica**: Fotos de feridas, erupções cutâneas ou imagens diagnósticas.
- **Gravações de Voz**: Processamento de áudio temporário para conversão de fala em texto.

## 3. Segurança de Dados e Criptografia
Todos os dados armazenados no dispositivo são protegidos pelo **SQLCipher**, fornecendo criptografia de nível militar (AES-256). Isso garante que, mesmo que o dispositivo físico seja perdido ou roubado, as informações do paciente não possam ser acessadas sem as credenciais autorizadas do aplicativo.

## 4. Permissões Necessárias
O aplicativo solicita permissões específicas para funcionar em campo:
- **Câmera**: Para capturar imagens clínicas para análise de IA.
- **Microfone**: Para permitir a gravação de sintomas sem o uso das mãos.
- **Armazenamento/Sistema de Arquivos**: Para armazenar os pesos do modelo de IA MedGemma (~3 GB) e o banco de dados local criptografado.

## 5. Acesso de Terceiros
Não existe **nenhum acesso de terceiros** aos seus dados. Como o aplicativo não se conecta à Internet para suas funções principais, nenhum dado pode ser compartilhado com anunciantes, provedores de análise ou agências governamentais.

## 6. Retenção de Dados
Os dados são retidos no seu dispositivo até que você exclua manualmente uma avaliação ou limpe os dados do aplicativo. Os usuários são responsáveis por realizar exclusões periódicas de dados de acordo com os protocolos da sua organização de saúde local.

## 7. Contato
Para dúvidas sobre a implementação técnica desta política de privacidade, entre em contato com a equipe de desenvolvimento em nosso repositório.

---
**Nota**: Ao usar o KintaMed Edge, você reconhece que é responsável pela segurança física do dispositivo e pela confidencialidade de quaisquer dados do paciente exibidos na tela.
