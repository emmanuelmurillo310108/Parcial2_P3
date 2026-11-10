# Punto 2 — Consulta de reportes sísmicos entre nodos

Requiere Elixir instalado y dos terminales en el mismo equipo.

1. Desde `punto-2/nodo-servidor`, ejecutar:
   `elixir --sname servidor@localhost --cookie sismos123 servidor.exs`
2. Desde `punto-2/nodo-cliente`, ejecutar:
   `elixir --sname cliente@localhost --cookie sismos123 cliente.exs`
3. Repetir el comando del cliente con otro nombre de nodo, por ejemplo:
   `elixir --sname cliente2@localhost --cookie sismos123 cliente.exs`

Se consultan C01 (con movimientos), C03 (sin movimientos), C99 (inexistente), el reporte general y :fin. El servidor sigue activo después de :fin. Los archivos se leen de nuevo para cada consulta.

Si se ejecuta en dos computadores distintos, reemplazar `localhost` en el código por el host real del servidor y configurar conectividad de nodos Erlang.
