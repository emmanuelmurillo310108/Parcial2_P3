defmodule ClienteSismos do
  def iniciar do
    Process.register(self(), :servicio_respuesta)
    servidor = {:servicio_sismos, :servidor@localhost}
    case Node.connect(:servidor@localhost) do
      true ->
        solicitudes = [{:reporte_ciudad, "C01"}, {:reporte_ciudad, "C03"},
                      {:reporte_ciudad, "C99"}, :reporte_general, :fin]
        enviar_solicitudes(servidor, solicitudes)
        recibir_respuestas(5)
      _ -> IO.puts("Error: no se pudo conectar al nodo servidor")
    end
  end

  defp enviar_solicitudes(_servidor, []), do: :ok
  defp enviar_solicitudes(servidor, [solicitud | resto]) do
    send(servidor, {self(), solicitud})
    enviar_solicitudes(servidor, resto)
  end

  defp recibir_respuestas(0), do: :ok
  defp recibir_respuestas(pendientes) do
    receive do
      :fin -> IO.puts("Fin de las respuestas")
      respuesta ->
        IO.puts("\n-----------------------------\n#{respuesta}")
        recibir_respuestas(pendientes - 1)
    end
  end
end

ClienteSismos.iniciar()
