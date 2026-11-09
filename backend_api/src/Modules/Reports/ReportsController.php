<?php

declare(strict_types=1);

final class ReportsController
{
    public function dashboard(): never
    {
        Response::ok($this->reports()->dashboard(QueryParams::only(['from', 'to'])));
    }

    public function salesDaily(): never
    {
        Response::ok($this->reports()->salesDaily(QueryParams::only(['from', 'to'])));
    }

    public function salesMonthly(): never
    {
        Response::ok($this->reports()->salesMonthly(QueryParams::only(['year'])));
    }

    public function purchases(): never
    {
        Response::ok($this->reports()->purchases(QueryParams::only(['from', 'to'])));
    }

    public function expensesByCategory(): never
    {
        Response::ok($this->reports()->expensesByCategory(QueryParams::only(['from', 'to'])));
    }

    public function topProducts(): never
    {
        Response::ok($this->reports()->topProductsReport(QueryParams::only(['from', 'to', 'limit'])));
    }

    public function financeMovements(): never
    {
        Response::ok($this->reports()->financeMovements(QueryParams::only(['from', 'to'])));
    }

    private function reports(): ReportsService
    {
        return new ReportsService(App::db(), App::config()['business_day_cutoff']);
    }
}
