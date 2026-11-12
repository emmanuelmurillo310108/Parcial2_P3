defmodule Ciudad do
  @moduledoc """
  Estructura que representa una ciudad del catálogo sísmico
  """
  defstruct id: "", nombre: "", habitantes: 0
end

defmodule Movimiento do
  @doc """
  Estructura que representa un movimiento sísmico validado
  """
  defstruct codigo: "", id_ciudad: "", inicio: "", final: "", magnitud: 0.0, profundidad: 0.0
end

defmodule SismosLocal do
  @doc """
  Módulo principal del código, se encarga de leer los archivos sísmicos, validar sus registros
  y generar un reporte por ciudad
  """

  @doc """
  Función main
  """
  def main do
    recursos = Path.join(__DIR__, "resources")
    principal_pid = self()
    spawn(fn ->
      enviar_lectura(principal_pid, :ciudades, Path.join(recursos, "ciudades.txt"))
    end)
    spawn(fn ->
      enviar_lectura(principal_pid, :movimientos, Path.join(recursos, "movimientos.txt"))
    end)
    recibir_lecturas(principal_pid, 2, %{})
  end

  @doc """
  Lee el archivo indicado y envía al receive el resultado etiquetado con su tipo
  """
  defp enviar_lectura(principal_pid, tipo, ruta) do
    resultado = leer_archivo(ruta, tipo)
    send(principal_pid, {:lectura, tipo, resultado})
  end

  @doc """
  Procesa los resultados cuando terminaron ambos trabajadores
  """
  defp recibir_lecturas(_pid, 0, resultados) do
    case {Map.get(resultados, :ciudades), Map.get(resultados, :movimientos)} do
      {{:ok, ciudades, rechazadas_ciudades}, {:ok, movimientos, rechazados_movimientos}} ->
        {movimientos, rechazados_ciudad} = validar_ciudades(movimientos, ciudades)
        reporte = generar_reporte(ciudades, movimientos, rechazadas_ciudades, rechazados_movimientos + rechazados_ciudad)
        IO.write(reporte)
        ruta = Path.join([__DIR__, "resources", "reporte_sismos.txt"])
        case File.write(ruta, reporte) do
          :ok -> IO.puts("Reporte guardado en #{ruta}")
          {:error, motivo} -> IO.puts("Error al guardar el reporte: #{:file.format_error(motivo)}")
        end
      _ ->
        Enum.each([:ciudades, :movimientos], fn tipo ->
          case Map.get(resultados, tipo) do
            {:error, motivo} -> IO.puts("Error al leer #{tipo}.txt: #{:file.format_error(motivo)}")
            _ -> :ok
          end
        end)
        IO.puts("No se reemplazó el reporte anterior")
    end
  end

  @doc """
  Espera las respuestas de los procesos trabajadores
  """
  defp recibir_lecturas(pid, pendientes, resultados) do
    receive do
      {:lectura, tipo, resultado} ->
        recibir_lecturas(pid, pendientes - 1, Map.put(resultados, tipo, resultado))
    end
  end

  @doc """
  Lee un archivo completo y convierte sus líneas en registros válidos
  """
  defp leer_archivo(ruta, tipo) do
    case File.read(ruta) do
      {:ok, contenido} ->
        lineas = String.split(contenido, "\n")
        {registros, rechazados} = procesar_lineas(lineas, tipo, [], 0)
        {:ok, registros, rechazados}
      {:error, motivo} -> {:error, motivo}
    end
  end

  @doc """
  Recorre las líneas del archivo y cuenta los registros rechazados
  """
  defp procesar_lineas([], _tipo, registros, rechazados), do:
    {Enum.reverse(registros), rechazados}

  defp procesar_lineas([linea | resto], tipo, registros, rechazados) do
    linea = String.trim(linea)
    if linea == "" do
      procesar_lineas(resto, tipo, registros, rechazados)
    else
      case parsear_registro(linea, tipo) do
        {:ok, registro} -> procesar_lineas(resto, tipo, [registro | registros], rechazados)
        :error -> procesar_lineas(resto, tipo, registros, rechazados + 1)
      end
    end
  end

  @doc """
  Convierte una línea de ciudades en una estructura del módulo Ciudad
  """
  defp parsear_registro(linea, :ciudades) do
    case String.split(linea, "@") do
      [id, nombre, habitantes] when id != "" and nombre != "" ->
        case Integer.parse(habitantes) do
          {numero, ""} when numero > 0 -> {:ok, %Ciudad{id: id, nombre: nombre, habitantes: numero}}
          _ -> :error
        end
      _ -> :error
    end
  end

  @doc """
  Convierte una línea de movimientos en una estructura del módulo Movimiento
  """
  defp parsear_registro(linea, :movimientos) do
    case String.split(linea, "@") do
      [codigo, id, inicio, final, magnitud, profundidad] when codigo != "" and id != "" and inicio != "" and final != "" ->
        with {:ok, _} <- Time.from_iso8601(inicio),
             {:ok, _} <- Time.from_iso8601(final),
             {mag, ""} when is_number(mag) <- Float.parse(magnitud),
             {prof, ""} when prof >= 0 <- Float.parse(profundidad) do
          {:ok, %Movimiento{codigo: codigo, id_ciudad: id, inicio: inicio, final: final, magnitud: mag, profundidad: prof}}
        else
          _ -> :error
        end
      _ -> :error
    end
  end

  @doc """
  Comprueba que cada movimiento esté asociado a una ciudad del catálogo
  """
  defp validar_ciudades(movimientos, ciudades) do
    ids = MapSet.new(Enum.map(ciudades, fn ciudad -> ciudad.id end))
    Enum.reduce(movimientos, {[], 0}, fn movimiento, {validos, rechazados} ->
      if MapSet.member?(ids, movimiento.id_ciudad) do
        {validos ++ [movimiento], rechazados}
      else
        {validos, rechazados + 1}
      end
    end)
  end

  @doc """
  Construye el texto completo del reporte de sismos por ciudad
  """
  defp generar_reporte(ciudades, movimientos, rechazadas_ciudades, rechazadas_movimientos) do
    ["REPORTE DE MOVIMIENTOS SÍSMICOS POR CIUDAD", "",
     reportar_ciudades(ciudades, movimientos),
     "Registros rechazados en ciudades: #{rechazadas_ciudades}",
     "Registros rechazados en movimientos: #{rechazadas_movimientos}", ""]
    |> Enum.join("\n")
  end

  @doc """
  Crea una sección del reporte para cada ciudad del catálogo
  """
  defp reportar_ciudades([], _movimientos), do: ""

  defp reportar_ciudades([ciudad | resto], movimientos) do
    asociados = movimientos_de_ciudad(movimientos, ciudad.id)
    detalle = detalle_movimientos(asociados)
    estadisticas = resumir(asociados)
    seccion = ["Ciudad: #{ciudad.nombre} (#{ciudad.id})", "Habitantes: #{ciudad.habitantes}", detalle,
      "Total de movimientos: #{estadisticas.cantidad}",
      "Movimiento de mayor magnitud: #{estadisticas.maximo}",
      "Profundidad promedio: #{estadisticas.promedio}", ""]
      |> Enum.join("\n")
    [seccion, reportar_ciudades(resto, movimientos)] |> Enum.join("\n")
  end

  @doc """
  Obtiene los movimientos que su identificador de ciudad coincida con el solicitado
  """
  defp movimientos_de_ciudad(movimientos, id), do: movimientos_de_ciudad(movimientos, id, [])

  @doc """
  Recorre los movimientos con un acumulador para devolver los asociados a una ciudad
  """
  defp movimientos_de_ciudad([], _id, encontrados), do: Enum.reverse(encontrados)

  defp movimientos_de_ciudad([movimiento | resto], id, encontrados) do
    if movimiento.id_ciudad == id do
      movimientos_de_ciudad(resto, id, [movimiento | encontrados])
    else
      movimientos_de_ciudad(resto, id, encontrados)
    end
  end

  @doc """
  Genera el texto con el detalle de los movimientos de una ciudad
  """
  defp detalle_movimientos([]), do: "Movimientos: Sin movimientos registrados"

  defp detalle_movimientos(movimientos) do
    "Movimientos:\n" <> listar_movimientos(movimientos)
  end

  @doc """
  Convierte cada movimiento en una línea legible para el reporte
  """
  defp listar_movimientos([]), do: ""

  defp listar_movimientos([movimiento | resto]) do
    linea = "  #{movimiento.codigo} | #{movimiento.inicio} | #{movimiento.final} | magnitud #{movimiento.magnitud} | profundidad #{movimiento.profundidad} km\n"
    linea <> listar_movimientos(resto)
  end

  @doc """
  Calcula la cantidad, el movimiento de mayor magnitud y la profundidad promedio
  """
  defp resumir(movimientos), do: resumir(movimientos, 0, nil, 0.0)

  @doc """
  Recorre los movimientos acumulando cantidad, magnitud máxima y suma de profundidades
  """
  defp resumir([], cantidad, maximo, suma) do
    if cantidad == 0 do
      %{cantidad: 0, maximo: "No aplica", promedio: "No aplica"}
    else
      %{cantidad: cantidad, maximo: "#{maximo.codigo} - #{maximo.magnitud}", promedio: :io_lib.format("~.2f", [suma / cantidad]) |> IO.iodata_to_binary()}
    end
  end

  defp resumir([movimiento | resto], cantidad, maximo, suma) do
    nuevo_maximo = if maximo == nil or movimiento.magnitud > maximo.magnitud, do: movimiento, else: maximo
    resumir(resto, cantidad + 1, nuevo_maximo, suma + movimiento.profundidad)
  end
end

SismosLocal.main()
