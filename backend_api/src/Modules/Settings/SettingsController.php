<?php

declare(strict_types=1);

final class SettingsController
{
    public function paymentSettings(): never
    {
        Response::ok($this->service()->get());
    }

    public function updatePaymentSettings(): never
    {
        Response::ok($this->service()->update(Request::json()));
    }

    public function uploadQr(): never
    {
        Response::ok($this->service()->replaceQr(ImageProcessor::uploadedFile($_FILES['image'] ?? null)));
    }

    private function service(): PaymentSettingsService
    {
        return new PaymentSettingsService(App::db(), App::user(), new Media(App::config()));
    }
}
