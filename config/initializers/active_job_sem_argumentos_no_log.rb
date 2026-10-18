# ramon: argumentos de job fora do log — senha, texto de cliente e payload de webhook não vão parar no log
# (ActiveJob loga "Performing X with arguments: ..." por padrão). Revisão pré-go-live A6.
ActiveSupport.on_load(:active_job) { self.log_arguments = false }
