defmodule Ciudad do
  defstruct id: "", nombre: "", habitantes: 0
end

defmodule Movimiento do
  defstruct codigo: "", id_ciudad: "", inicio: "", final: "", magnitud: 0.0, profundidad: 0.0
end

defmodule ServicioSismos do
  def iniciar do
    Process.register(spawn(fn -> atender() end), :servicio_sismos)
    IO.puts("Servidor listo: #{inspect(Node.self())}")
  end

  defp atender do
    receive do
      {destino, {:reporte_ciudad, id}} ->
        send(destino, reporte_solicitado(id))
        atender()
      {destino, :reporte_general} ->
        send(destino, reporte_solicitado(:general))
        atender()
      {destino, :fin} ->
        send(destino, :fin)
        atender()
      _ -> atender()
    end
  end

  defp reporte_solicitado(solicitud) do
    principal = self()
    recursos = Path.join(__DIR__, "resources")
    spawn(fn -> send(principal, {:lectura, :ciudades, leer(Path.join(recursos, "ciudades.txt"), :ciudades)}) end)
    spawn(fn -> send(principal, {:lectura, :movimientos, leer(Path.join(recursos, "movimientos.txt"), :movimientos)}) end)
    resultados = recibir_lecturas(2, %{})
    case {Map.get(resultados, :ciudades), Map.get(resultados, :movimientos)} do
      {{:ok, ciudades, rc}, {:ok, movimientos, rm}} ->
        ids = MapSet.new(Enum.map(ciudades, fn ciudad -> ciudad.id end))
        {validos, extra} = Enum.reduce(movimientos, {[], 0}, fn m, {lista, n} ->
          if MapSet.member?(ids, m.id_ciudad), do: {[m | lista], n}, else: {lista, n + 1}
        end)
        validos = Enum.reverse(validos)
        case solicitud do
          :general ->
          mayores = movimientos_mayores_A20(validos)
          detalle_mayores = if mayores == [], do: "No hay movimientos con profundidad mayor a 20 km", else: listar(mayores)
            "REPORTE GENERAL DE SISMOS\n\n" <>
              Enum.map_join(ciudades, "\n", fn ciudad -> reporte_ciudad(ciudad, validos) end) <>
          "\nMovimientos con profundidad mayor a 20 km:\n#{detalle_mayores}\n" <>
              "\nRechazados ciudades: #{rc}\nRechazados movimientos: #{rm + extra}\n"
          id ->
            case Enum.find(ciudades, fn ciudad -> ciudad.id == id end) do
              nil -> "La ciudad no está registrada"
              ciudad -> reporte_ciudad(ciudad, validos)
            end
        end
      {{:error, motivo}, _} -> "Error al leer ciudades.txt: #{:file.format_error(motivo)}"
      {_, {:error, motivo}} -> "Error al leer movimientos.txt: #{:file.format_error(motivo)}"
    end
  end

  defp recibir_lecturas(0, resultados), do: resultados
  defp recibir_lecturas(pendientes, resultados) do
    receive do
      {:lectura, tipo, resultado} -> recibir_lecturas(pendientes - 1, Map.put(resultados, tipo, resultado))
    end
  end

  defp leer(ruta, tipo) do
    case File.read(ruta) do
      {:error, motivo} -> {:error, motivo}
      {:ok, contenido} ->
        {registros, rechazados} = procesar(String.split(contenido, "\n"), tipo, [], 0)
        {:ok, registros, rechazados}
    end
  end

  defp procesar([], _tipo, acumulados, rechazados), do: {Enum.reverse(acumulados), rechazados}
  defp procesar([linea | resto], tipo, acumulados, rechazados) do
    linea = String.trim(linea)
    cond do
      linea == "" -> procesar(resto, tipo, acumulados, rechazados)
      true ->
        case convertir(linea, tipo) do
          {:ok, registro} -> procesar(resto, tipo, [registro | acumulados], rechazados)
          :error -> procesar(resto, tipo, acumulados, rechazados + 1)
        end
    end
  end

  defp convertir(linea, :ciudades) do
    case String.split(linea, "@") do
      [id, nombre, habitantes] when id != "" and nombre != "" ->
        case Integer.parse(habitantes) do
          {n, ""} when n > 0 -> {:ok, %Ciudad{id: id, nombre: nombre, habitantes: n}}
          _ -> :error
        end
      _ -> :error
    end
  end
  defp convertir(linea, :movimientos) do
    case String.split(linea, "@") do
      [codigo, id, inicio, final, magnitud, profundidad] when codigo != "" and id != "" ->
        with {:ok, _} <- Time.from_iso8601(inicio),
             {:ok, _} <- Time.from_iso8601(final),
             {mag, ""} <- Float.parse(magnitud),
             {prof, ""} when prof >= 0 <- Float.parse(profundidad) do
          {:ok, %Movimiento{codigo: codigo, id_ciudad: id, inicio: inicio, final: final, magnitud: mag, profundidad: prof}}
        else
          _ -> :error
        end
      _ -> :error
    end
  end
defp movimientos_mayores_A20 (movimientos) do
    Enum.filter(movimientos, fn m -> m.profundidad > 20.0 end)
  end 
  defp reporte_ciudad(ciudad, movimientos) do
    asociados = Enum.filter(movimientos, fn m -> m.id_ciudad == ciudad.id end)
    {cantidad, maximo, suma} = resumir(asociados, 0, nil, 0.0)
    detalle = if cantidad == 0, do: "Sin movimientos registrados\n", else: listar(asociados)
    mayor = if maximo == nil, do: "No aplica", else: "#{maximo.codigo} - #{maximo.magnitud}"
    promedio = if cantidad == 0, do: "No aplica", else: :io_lib.format("~.2f", [suma / cantidad]) |> IO.iodata_to_binary()
    "Ciudad: #{ciudad.nombre} (#{ciudad.id})\nHabitantes: #{ciudad.habitantes}\n" <>
      "Movimientos:\n#{detalle}Total de movimientos: #{cantidad}\n" <>
      "Movimiento de mayor magnitud: #{mayor}\nProfundidad promedio: #{promedio}\n"
  end

  defp listar([]), do: ""
  defp listar([m | resto]) do
    "  #{m.codigo} | #{m.inicio} | #{m.final} | magnitud #{m.magnitud} | profundidad #{m.profundidad} km\n" <> listar(resto)
  end

  defp resumir([], cantidad, maximo, suma), do: {cantidad, maximo, suma}
  defp resumir([m | resto], cantidad, maximo, suma) do
    nuevo = if maximo == nil or m.magnitud > maximo.magnitud, do: m, else: maximo
    resumir(resto, cantidad + 1, nuevo, suma + m.profundidad)
  end
end

ServicioSismos.iniciar()
Process.sleep(:infinity)
