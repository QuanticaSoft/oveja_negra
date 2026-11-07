<?php

declare(strict_types=1);

final class AuthController
{
    public function login(): never
    {
        $input = Request::json();
        Response::ok($this->service()->login(
            $input['identifier'] ?? null, $input['password'] ?? null, Request::ip(), Request::userAgent()));
    }

    public function refresh(): never
    {
        Response::ok($this->service()->refresh(Request::json()['refresh_token'] ?? null, Request::userAgent()));
    }

    public function logout(): never
    {
        $this->service()->logout(Request::json()['refresh_token'] ?? null);
        Response::ok(null);
    }

    public function me(): never
    {
        Response::ok(App::user()->toArray());
    }

    public function changePassword(): never
    {
        $input = Request::json();
        Response::ok($this->service()->changeOwnPassword(
            App::user(), $input['current_password'] ?? null, $input['new_password'] ?? null, Request::userAgent()));
    }

    private function service(): AuthService
    {
        return new AuthService(App::db(), App::config(), App::jwtSecret());
    }
}
