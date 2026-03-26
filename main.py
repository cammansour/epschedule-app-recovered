from flask import abort, redirect, request, session

from app import app, init_app

init_app()

if __name__ == "__main__":
    @app.route("/login")
    def handle_login():
        if "u" not in request.args:
            return abort(400)

        session["username"] = request.args["u"]
        return redirect("/")

    app.run(host="127.0.0.1", port=8080, debug=True)
