"""Tracing OpenTelemetry dla meme-gen (LAB 9). Kopiujesz ten plik do app/meme-gen/.

Działa tylko wtedy, gdy są zainstalowane pakiety opentelemetry (requirements.txt)
i ustawiona zmienna OTEL_EXPORTER_OTLP_ENDPOINT. W innym wypadku każda funkcja
jest pusta i aplikacja działa dokładnie jak wcześniej (testy, start-lab, LAB 1-8).

Konfiguracja przez standardowe zmienne OpenTelemetry (manifest Knative):
  OTEL_EXPORTER_OTLP_ENDPOINT  adres Collectora, np. http://otel-collector.observability:4318
  OTEL_SERVICE_NAME            nazwa usługi w Tempo (domyślnie meme-gen)
  OTEL_BSP_SCHEDULE_DELAY      co ile ms wysyłać paczkę spanów (domyślnie 5000)
"""
import os
from contextlib import contextmanager

try:
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.propagate import extract
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import BatchSpanProcessor
    from opentelemetry.trace import SpanKind, Status, StatusCode

    ENABLED = bool(os.environ.get("OTEL_EXPORTER_OTLP_ENDPOINT"))
except ImportError:
    ENABLED = False

if ENABLED:
    _provider = TracerProvider(resource=Resource.create({
        "service.name": os.environ.get("OTEL_SERVICE_NAME", "meme-gen"),
        "service.version": os.environ.get("APP_VERSION", "dev"),
        "knative.revision": os.environ.get("K_REVISION", "lokalnie"),
    }))
    _provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))  # endpoint z OTEL_EXPORTER_OTLP_ENDPOINT
    trace.set_tracer_provider(_provider)
    _tracer = trace.get_tracer("meme-gen")


@contextmanager
def request_span(method, path, headers):
    """Span całego żądania. Rodzic pochodzi z nagłówka traceparent, który ustawia queue-proxy Knative,
    więc span aplikacji dołącza do trace'a activatora i queue-proxy. /healthz (probe co kilka sekund) pomijamy."""
    if not ENABLED or path == "/healthz":
        yield None
        return
    with _tracer.start_as_current_span(f"{method} {path}", context=extract(headers), kind=SpanKind.SERVER,
                                       attributes={"http.request.method": method, "url.path": path}) as span:
        yield span


@contextmanager
def span(name, **attributes):
    """Span fragmentu pracy wewnątrz żądania (np. renderowania mema) z atrybutami do wyszukiwania w Tempo."""
    if not ENABLED:
        yield None
        return
    with _tracer.start_as_current_span(name, attributes=attributes) as s:
        yield s


def set_status(span_, status_code):
    """Kod HTTP na spanie; 5xx oznacza span jako błąd (czerwony w Grafanie, filtr status=error w Tempo)."""
    if span_ is None:
        return
    span_.set_attribute("http.response.status_code", status_code)
    if status_code >= 500:
        span_.set_status(Status(StatusCode.ERROR))


def trace_id():
    """Identyfikator bieżącego trace'a (32 znaki hex) do logu JSON albo None."""
    if not ENABLED:
        return None
    ctx = trace.get_current_span().get_span_context()
    return format(ctx.trace_id, "032x") if ctx.is_valid else None
