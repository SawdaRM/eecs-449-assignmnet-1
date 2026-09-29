"""A message that disappears after a few seconds. Pass "" to hide it."""

import from react { useEffect }

def:pub Toast(message: str, onClear: Callable[[], None]) -> JsxElement {
    # Always return the cleanup function: React treats a returned `null`
    # as a (broken) cleanup and crashes on the next update.
    useEffect(lambda {
        timer = setTimeout(lambda {
            if message {
                onClear();
            }
        }, 3500);
        return lambda { clearTimeout(timer); };
    }, [message]);

    if not message {
        return <></>;
    }
    return <div className="toast" role="status">{message}</div>;
}
